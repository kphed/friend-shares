// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {ExponentialCurve} from "sudoswap/bonding-curves/ExponentialCurve.sol";

/**
 * @notice Buy and sell shares of your friends. Based on FriendTech.
 * @author kp (ppmoon69.eth)
 */
contract FriendShares is Ownable, ExponentialCurve {
    using SafeTransferLib for address;
    using SafeCastLib for uint256;

    // Prevents registration spam and supports the protocol.
    uint256 private constant REGISTRATION_FEE = 0.05 ether;

    // 1% fee goes to the protocol.
    uint256 private constant PROTOCOL_FEE_PERCENT = 1e16;

    // 4% fee goes to the shares user.
    uint256 private constant USER_FEE_PERCENT = 4e16;

    // The price for the first share.
    uint256 private constant INITIAL_PRICE = 0.001 ether;

    // Price changes by 0.01% for each share bought or sold.
    uint128 private constant EXPONENTIAL_CURVE_DELTA = 1e18 + 1e14;

    mapping(string user => address wallet) public users;
    mapping(string user => mapping(address owner => uint256 balance))
        public sharesBalance;
    mapping(string user => uint256 supply) public sharesSupply;
    mapping(string user => uint256 price) public sharesPrice;

    event RegisterUser(string indexed user, address indexed wallet);
    event BuyShares(
        address indexed trader,
        string indexed user,
        uint256 shares,
        uint256 value
    );
    event SellShares(
        address indexed trader,
        string indexed user,
        uint256 shares,
        uint256 value
    );

    error AlreadyRegistered();
    error InvalidUser();
    error InvalidWallet();
    error InsufficientPayment();
    error InsufficientSupply();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function registerUser(
        string calldata user,
        address wallet
    ) external payable {
        if (users[user] != address(0)) revert AlreadyRegistered();
        if (bytes(user).length == 0) revert InvalidUser();
        if (wallet == address(0)) revert InvalidWallet();

        // The minimum `msg.value` should be the registration fee but we will accept donations.
        if (msg.value < REGISTRATION_FEE) revert InsufficientPayment();

        users[user] = wallet;

        emit RegisterUser(user, wallet);

        // Send the registration fee to the protocol.
        owner().safeTransferETH(msg.value);
    }

    function getBuyPrice(
        string calldata user,
        uint256 amount
    )
        public
        view
        returns (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        )
    {
        uint256 spotPrice = sharesPrice[user];

        // Set the initial spot price if it has not yet been set.
        if (spotPrice == 0) spotPrice = INITIAL_PRICE;

        (, newSpotPrice, , buyerPayment, userFee, protocolFee) = getBuyInfo(
            spotPrice.toUint128(),
            EXPONENTIAL_CURVE_DELTA,
            amount,
            USER_FEE_PERCENT,
            PROTOCOL_FEE_PERCENT
        );
    }

    function getSellPrice(
        string calldata user,
        uint256 amount
    )
        public
        view
        returns (
            uint128 newSpotPrice,
            uint256 sellerProceeds,
            uint256 userFee,
            uint256 protocolFee
        )
    {
        (, newSpotPrice, , sellerProceeds, userFee, protocolFee) = getSellInfo(
            sharesPrice[user].toUint128(),
            EXPONENTIAL_CURVE_DELTA,
            amount,
            USER_FEE_PERCENT,
            PROTOCOL_FEE_PERCENT
        );
    }

    function buyShares(string calldata user, uint256 amount) external payable {
        address userWallet = users[user];

        if (userWallet == address(0)) revert InvalidUser();

        (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        ) = getBuyPrice(user, amount);

        // Check if the payment is enough for the shares, protocol, and user fees.
        if (msg.value < buyerPayment) revert InsufficientPayment();

        // Update the user's shares supply and price, and the trader's balance before making external calls.
        unchecked {
            // Safe to perform unchecked arithmetic due to the `msg.value` check above.
            sharesSupply[user] += amount;
            sharesBalance[user][msg.sender] += amount;
        }

        sharesPrice[user] = newSpotPrice;

        emit BuyShares(msg.sender, user, amount, buyerPayment);

        // Distribute ETH fees.
        owner().safeTransferETH(protocolFee);
        userWallet.safeTransferETH(userFee);

        // Refund excess ETH.
        // Will not underflow since `msg.value` is GTE or equal to `buyerPayment` (checked above).
        unchecked {
            if (msg.value - buyerPayment != 0) {
                msg.sender.safeTransferETH(msg.value - buyerPayment);
            }
        }
    }

    function sellShares(string calldata user, uint256 amount) external {
        address userWallet = users[user];

        if (userWallet == address(0)) revert InvalidUser();

        (
            uint128 newSpotPrice,
            uint256 sellerProceeds,
            uint256 userFee,
            uint256 protocolFee
        ) = getSellPrice(user, amount);

        // Throws with an arithmetic underflow error if the sell amount exceeds the current supply.
        sharesSupply[user] -= amount;

        // Throws with an arithmetic underflow error if `msg.sender` doesn't have enough shares to sell.
        sharesBalance[user][msg.sender] -= amount;

        sharesPrice[user] = newSpotPrice;

        emit SellShares(msg.sender, user, amount, sellerProceeds);

        // Distribute sales proceeds to shares seller (fees have already been deducted).
        msg.sender.safeTransferETH(sellerProceeds);

        // Distribute fees to the protocol and user.
        owner().safeTransferETH(protocolFee);
        userWallet.safeTransferETH(userFee);
    }
}
