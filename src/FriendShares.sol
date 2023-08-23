// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

    // The price for the first share.
    uint256 private constant INITIAL_PRICE = 0.01 ether;

    // Price changes by 0.1% for each share bought or sold.
    uint128 private constant EXPONENTIAL_CURVE_DELTA = 1e18 + 1e15;

    mapping(address subject => mapping(address owner => uint256 balance)) public sharesBalance;
    mapping(address subject => uint256 supply) public sharesSupply;
    mapping(address subject => uint256 price) public sharesPrice;

    event BuyShares(
        address indexed trader,
        address indexed subject,
        uint256 shares,
        uint256 totalPayment,
        uint256 protocolFee,
        uint256 subjectFee
    );
    event SellShares(
        address indexed trader,
        address indexed subject,
        uint256 shares,
        uint256 salesProceeds,
        uint256 protocolFee,
        uint256 subjectFee
    );

    error InsufficientPayment();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function buyShares(address sharesSubject, uint256 amount) external payable {
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
        sharesBalance[sharesSubject][msg.sender] += amount;

        emit BuyShares(msg.sender, sharesSubject, amount, totalPayment, protocolFee, subjectFee);

        // Distribute ETH fees.
        owner().safeTransferETH(protocolFee);
        sharesSubject.safeTransferETH(subjectFee);

        // Refund excess ETH.
        if (msg.value - totalPayment != 0) {
            msg.sender.safeTransferETH(msg.value - totalPayment);
        }
    }

    function sellShares(address sharesSubject, uint256 amount) external {
        (, uint128 newSpotPrice,, uint256 salesProceeds, uint256 subjectFee, uint256 protocolFee) = getSellInfo(
            sharesPrice[sharesSubject].toUint128(),
            EXPONENTIAL_CURVE_DELTA,
            amount,
            PROTOCOL_FEE_PERCENT,
            SUBJECT_FEE_PERCENT
        );

        uint256 supply = sharesSupply[sharesSubject];

        // Throws with an arithmetic underflow error if the sell amount exceeds the current supply.
        sharesSupply[sharesSubject] = supply - amount;

        // Throws with an arithmetic underflow error if `msg.sender` doesn't have enough shares to sell.
        sharesBalance[sharesSubject][msg.sender] -= amount;

        sharesPrice[sharesSubject] = newSpotPrice;

        emit SellShares(msg.sender, sharesSubject, amount, salesProceeds, protocolFee, subjectFee);

        // Distribute sales proceeds to seller (fees have already been deducted).
        msg.sender.safeTransferETH(salesProceeds);

        // Distribute fees to the protocol and subject.
        owner().safeTransferETH(protocolFee);
        sharesSubject.safeTransferETH(subjectFee);
    }
}
