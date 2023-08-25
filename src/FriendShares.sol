// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";
import {ExponentialCurve} from "sudoswap/bonding-curves/ExponentialCurve.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

/**
 * @notice Buy and sell shares of your friends. Based on FriendTech.
 * @author kp (ppmoon69.eth)
 */
contract FriendShares is Ownable, ExponentialCurve {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;
    using SafeCastLib for uint256;

    struct User {
        uint128 supply;
        uint128 price;
        mapping(address owner => uint256 balance) balanceOf;
    }

    // Price changes by 0.01% for each share bought or sold.
    uint128 private constant EXPONENTIAL_CURVE_DELTA = 10001e14;

    // The price for the first share.
    uint128 private constant INITIAL_PRICE = 0.001 ether;

    // 8% fee goes to the shares user.
    // FixedPointMathLib.WAD.mulDiv(8, 100).
    uint256 public constant USER_FEE_PERCENT = 8e16;

    // 2% fee goes to the protocol.
    // FixedPointMathLib.WAD.mulDiv(2, 100).
    uint256 public constant PROTOCOL_FEE_PERCENT = 2e16;

    mapping(address user => User) public users;

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

    error InsufficientPayment();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function balanceOf(
        address user,
        address owner
    ) external view returns (uint256) {
        return users[user].balanceOf[owner];
    }

    function _getBuyPrice(
        uint128 spotPrice,
        uint256 amount
    )
        public
        pure
        returns (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        )
    {
        (, newSpotPrice, , buyerPayment, userFee, protocolFee) = getBuyInfo(
            spotPrice,
            EXPONENTIAL_CURVE_DELTA,
            amount,
            USER_FEE_PERCENT,
            PROTOCOL_FEE_PERCENT
        );
    }

    function _getSellPrice(
        uint128 spotPrice,
        uint256 amount
    )
        internal
        pure
        returns (
            uint128 newSpotPrice,
            uint256 sellerProceeds,
            uint256 userFee,
            uint256 protocolFee
        )
    {
        (, newSpotPrice, , sellerProceeds, userFee, protocolFee) = getSellInfo(
            spotPrice,
            EXPONENTIAL_CURVE_DELTA,
            amount,
            USER_FEE_PERCENT,
            PROTOCOL_FEE_PERCENT
        );
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
        uint128 spotPrice = users[user].price;

        // Set the initial spot price if it has not yet been set.
        if (spotPrice == 0) spotPrice = INITIAL_PRICE;

        return _getBuyPrice(spotPrice, amount);
    }

    function getSellPrice(
        address user,
        uint256 amount
    ) public view returns (uint128, uint256, uint256, uint256) {
        return _getSellPrice(users[user].price, amount);
    }

    function buyShares(address user, uint256 amount) external payable {
        User storage _user = users[user];
        (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        ) = _getBuyPrice(_user.price, amount);

        // Check if the payment is enough for the shares, protocol, and user fees.
        if (msg.value < buyerPayment) revert InsufficientPayment();

        // Update the user's shares supply and price, and the trader's balance before making external calls.
        unchecked {
            // Safe to perform unchecked arithmetic due to the `msg.value` check above.
            _user.balanceOf[msg.sender] += amount;
            _user.supply += amount.toUint128();
        }

        _user.price = newSpotPrice;

        emit BuyShares(msg.sender, user, amount, buyerPayment);

        user.safeTransferETH(userFee);
        owner().safeTransferETH(protocolFee);

        // Will not underflow since `msg.value` is GTE or equal to `buyerPayment` (checked above).
        unchecked {
            if (msg.value - buyerPayment != 0)
                msg.sender.safeTransferETH(msg.value - buyerPayment);
        }
    }

    function sellShares(address user, uint256 amount) external {
        User storage _user = users[user];
        (
            uint128 newSpotPrice,
            uint256 sellerProceeds,
            uint256 userFee,
            uint256 protocolFee
        ) = _getSellPrice(_user.price, amount);

        // Throws with an arithmetic underflow error if `msg.sender` doesn't have enough shares to sell.
        _user.balanceOf[msg.sender] -= amount;

        // Will not underflow if the above doesn't since share balances should never exceed the supply.
        unchecked {
            _user.supply -= amount.toUint128();
        }

        _user.price = newSpotPrice;

        emit SellShares(msg.sender, user, amount, sellerProceeds);

        // Distribute sales proceeds to shares seller (fees have already been deducted).
        msg.sender.safeTransferETH(sellerProceeds);

        user.safeTransferETH(userFee);
        owner().safeTransferETH(protocolFee);
    }
}
