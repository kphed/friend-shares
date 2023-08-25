// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

    // The price for the first share.
    uint128 private constant INITIAL_PRICE = 0.001 ether;

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

    function buyShares(address user, uint256 amount) external payable {
        User storage _user = users[user];
        (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        ) = getBuyInfo(_user.price != 0 ? _user.price : INITIAL_PRICE, amount);

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

    function sellShares(address user, uint128 amount) external {
        User storage _user = users[user];
        (
            uint128 newSpotPrice,
            uint256 sellerProceeds,
            uint256 userFee,
            uint256 protocolFee
        ) = getSellInfo(_user.price, amount);

        // Throws with an arithmetic underflow error if `msg.sender` doesn't have enough shares to sell.
        _user.balanceOf[msg.sender] -= amount;

        // Will not underflow if the above doesn't since share balances should never exceed the supply.
        unchecked {
            _user.supply -= amount;
        }

        _user.price = newSpotPrice;

        emit SellShares(msg.sender, user, amount, sellerProceeds);

        // Distribute sales proceeds to shares seller (fees have already been deducted).
        msg.sender.safeTransferETH(sellerProceeds);

        user.safeTransferETH(userFee);
        owner().safeTransferETH(protocolFee);
    }
}
