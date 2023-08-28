// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ExponentialCurve} from "src/lib/ExponentialCurve.sol";

/**
 * @notice Buy and sell shares of your friends. Based on FriendTech.
 * @author kp (ppmoon69.eth)
 */
contract FriendShares is ExponentialCurve {
    using SafeTransferLib for address;

    struct User {
        uint128 supply;
        uint128 price;
        mapping(address owner => uint256 balance) balanceOf;
    }

    address public immutable protocol;
    mapping(address user => User) public users;

    event BuyShares(
        address indexed trader,
        address indexed user,
        address indexed recipient,
        uint256 shares,
        uint256 value
    );
    event SellShares(
        address indexed trader,
        address indexed user,
        address indexed recipient,
        uint256 shares,
        uint256 value
    );

    error InsufficientPayment();

    constructor(address _protocol) {
        protocol = _protocol;
    }

    function balanceOf(
        address user,
        address owner
    ) external view returns (uint256) {
        return users[user].balanceOf[owner];
    }

    function buyShares(
        address user,
        uint128 amount,
        address recipient
    ) external payable {
        User storage _user = users[user];
        (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        ) = getBuyInfo(_user.price, amount);

        // Check if the payment is enough for the shares, protocol, and user fees.
        if (msg.value < buyerPayment) revert InsufficientPayment();

        // Update the user's shares supply and price, and the trader's balance before making external calls.
        unchecked {
            // Safe to perform unchecked arithmetic due to the `msg.value` check above.
            _user.balanceOf[recipient] += amount;
            _user.supply += amount;
            _user.price = newSpotPrice;
        }

        emit BuyShares(msg.sender, user, recipient, amount, buyerPayment);

        user.safeTransferETH(userFee);
        protocol.safeTransferETH(protocolFee);

        // Will not underflow since `msg.value` is GTE or equal to `buyerPayment` (checked above).
        unchecked {
            if (msg.value - buyerPayment != 0)
                msg.sender.safeTransferETH(msg.value - buyerPayment);
        }
    }

    function sellShares(
        address user,
        uint128 amount,
        address recipient
    ) external {
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
            _user.price = newSpotPrice;
        }

        emit SellShares(msg.sender, user, recipient, amount, sellerProceeds);

        // Distribute sales proceeds to the recipient specified by the seller (fees have already been deducted).
        recipient.safeTransferETH(sellerProceeds);

        user.safeTransferETH(userFee);
        protocol.safeTransferETH(protocolFee);
    }
}
