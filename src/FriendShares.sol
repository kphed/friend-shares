// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

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

    // 1% fee goes to the protocol.
    uint256 private constant PROTOCOL_FEE_PERCENT = 2e16;

    // 4% fee goes to the shares user.
    uint256 private constant USER_FEE_PERCENT = 8e16;

    // The price for the first share.
    uint256 private constant INITIAL_PRICE = 0.001 ether;

    // Price changes by 0.01% for each share bought or sold.
    uint128 private constant EXPONENTIAL_CURVE_DELTA = 1e18 + 1e14;

    mapping(address user => mapping(address owner => uint256 balance))
        public sharesBalance;
    mapping(address user => uint256 supply) public sharesSupply;
    mapping(address user => uint256 price) public sharesPrice;

    event BuyShares(
        address indexed trader,
        address indexed user,
        uint256 shares,
        uint256 value
    );
    event SellShares(
        address indexed trader,
        address indexed user,
        uint256 shares,
        uint256 value
    );

    error InvalidUser();
    error InsufficientPayment();
    error InsufficientSupply();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function getBuyPrice(
        address user,
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
        address user,
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

    function buyShares(address user, uint256 amount) external payable {
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
        user.safeTransferETH(userFee);

        // Refund excess ETH.
        // Will not underflow since `msg.value` is GTE or equal to `buyerPayment` (checked above).
        unchecked {
            if (msg.value - buyerPayment != 0)
                msg.sender.safeTransferETH(msg.value - buyerPayment);
        }
    }

    function sellShares(address user, uint256 amount) external {
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
        user.safeTransferETH(userFee);
    }
}
