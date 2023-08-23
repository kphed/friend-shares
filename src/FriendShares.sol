// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {ExponentialCurve} from "sudoswap/bonding-curves/ExponentialCurve.sol";

contract FriendShares is Ownable, ExponentialCurve {
    using SafeTransferLib for address;
    using SafeCastLib for uint256;

    // 1% fee goes to the protocol.
    uint256 private constant PROTOCOL_FEE_PERCENT = 1e16;

    // 4% fee goes to the shares subject.
    uint256 private constant SUBJECT_FEE_PERCENT = 4e16;
    uint256 private constant FEE_PERCENT_BASE = 10_000;
    uint256 private constant INITIAL_PRICE = 0.001 ether;

    // Price changes by 1% for each share bought or sold.
    uint128 private constant EXPONENTIAL_CURVE_DELTA = 1e18 + 1e16;

    // SharesSubject => (Holder => Balance)
    mapping(address => mapping(address => uint256)) public sharesBalance;

    // SharesSubject => Supply
    mapping(address => uint256) public sharesSupply;

    // Shares price.
    mapping(address => uint256) public sharesPrice;

    event Trade(
        address indexed trader,
        address indexed subject,
        bool indexed isBuy,
        uint256 shareAmount,
        uint256 ethAmount,
        uint256 protocolEthAmount,
        uint256 subjectEthAmount,
        uint256 supply
    );

    error InsufficientPayment();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1) * (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / 16000;
    }

    function getSellPrice(address sharesSubject, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[sharesSubject] - amount, amount);
    }

    function getSellPriceAfterFee(address sharesSubject, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(sharesSubject, amount);
        uint256 protocolFee = price * PROTOCOL_FEE_PERCENT / FEE_PERCENT_BASE;
        uint256 subjectFee = price * SUBJECT_FEE_PERCENT / FEE_PERCENT_BASE;
        return price - protocolFee - subjectFee;
    }

    function buyShares(address sharesSubject, uint256 amount) public payable {
        uint256 spotPrice = sharesPrice[sharesSubject];

        // Set the initial spot price if it has not yet been set.
        if (spotPrice == 0) spotPrice = INITIAL_PRICE;

        (, uint128 newSpotPrice,, uint256 totalPayment, uint256 subjectFee, uint256 protocolFee) = getBuyInfo(
            spotPrice.toUint128(), EXPONENTIAL_CURVE_DELTA, amount, PROTOCOL_FEE_PERCENT, SUBJECT_FEE_PERCENT
        );

        // Check if the payment is enough for the shares, protocol, and subject fees.
        if (msg.value < totalPayment) revert InsufficientPayment();

        // Cache the current shares supply value to save gas.
        uint256 supply = sharesSupply[sharesSubject];

        // Update the subject's shares supply and price, and the trader's balance before making external calls.
        sharesSupply[sharesSubject] = supply + amount;
        sharesPrice[sharesSubject] = newSpotPrice;
        sharesBalance[sharesSubject][msg.sender] = sharesBalance[sharesSubject][msg.sender] + amount;

        emit Trade(
            msg.sender,
            sharesSubject,
            true,
            amount,
            totalPayment - subjectFee - protocolFee,
            protocolFee,
            subjectFee,
            supply + amount
        );

        // Distribute ETH fees.
        owner().safeTransferETH(protocolFee);
        sharesSubject.safeTransferETH(subjectFee);

        // Refund excess ETH.
        if (msg.value - totalPayment != 0) {
            msg.sender.safeTransferETH(msg.value - totalPayment);
        }
    }

    function sellShares(address sharesSubject, uint256 amount) public payable {
        uint256 supply = sharesSupply[sharesSubject];

        require(supply > amount, "Cannot sell the last share");

        uint256 price = getPrice(supply - amount, amount);
        uint256 protocolFee = price * PROTOCOL_FEE_PERCENT / FEE_PERCENT_BASE;
        uint256 subjectFee = price * SUBJECT_FEE_PERCENT / FEE_PERCENT_BASE;

        require(sharesBalance[sharesSubject][msg.sender] >= amount, "Insufficient shares");

        sharesBalance[sharesSubject][msg.sender] = sharesBalance[sharesSubject][msg.sender] - amount;
        sharesSupply[sharesSubject] = supply - amount;

        emit Trade(msg.sender, sharesSubject, false, amount, price, protocolFee, subjectFee, supply - amount);

        // Distribute ETH fees.
        msg.sender.safeTransferETH(price - protocolFee - subjectFee);
        owner().safeTransferETH(protocolFee);
        sharesSubject.safeTransferETH(subjectFee);
    }
}
