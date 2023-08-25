// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ExponentialCurve} from "src/lib/ExponentialCurve.sol";
import {FriendShares} from "src/FriendShares.sol";

contract FriendSharesTest is Test, ExponentialCurve {
    FriendShares public immutable friend = new FriendShares(address(this));

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

    receive() external payable {}

    function _calculateSharesBuyPrice(
        address user,
        uint256 amount
    )
        private
        view
        returns (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        )
    {
        (, uint128 spotPrice) = friend.users(user);
        (newSpotPrice, buyerPayment, userFee, protocolFee) = getBuyInfo(
            spotPrice,
            amount
        );
    }

    /*//////////////////////////////////////////////////////////////
                             buyShares
    //////////////////////////////////////////////////////////////*/

    function testCannotBuyShares_InsufficientPayment() external {
        address user = address(1);
        uint128 amount = 1;

        vm.expectRevert(FriendShares.InsufficientPayment.selector);

        friend.buyShares{value: 0}(user, amount);
    }

    function testBuyShares() external {
        address msgSender = address(1);
        address user = address(2);
        uint128 amount = 1;
        (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        ) = _calculateSharesBuyPrice(user, amount);
        uint256 userBalanceBefore = user.balance;
        uint256 protocolBalanceBefore = address(this).balance;
        (uint256 supply, uint256 price) = friend.users(user);

        assertEq(0, supply);
        assertEq(0, price);
        assertEq(0, friend.balanceOf(user, msgSender));

        vm.deal(msgSender, buyerPayment);
        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(friend));

        emit BuyShares(msgSender, user, amount, buyerPayment);

        friend.buyShares{value: buyerPayment}(user, amount);

        (supply, price) = friend.users(user);

        assertEq(amount, supply);
        assertEq(newSpotPrice, price);
        assertEq(amount, friend.balanceOf(user, msgSender));
        assertEq(userBalanceBefore + userFee, user.balance);
        assertEq(protocolBalanceBefore + protocolFee, address(this).balance);
    }

    function testBuySharesFuzz(uint16 amount, uint16 extraValue) external {
        vm.assume(amount != 0);

        address msgSender = address(1);
        address user = address(2);
        (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        ) = _calculateSharesBuyPrice(user, amount);

        vm.deal(msgSender, buyerPayment + extraValue);

        uint256 msgSenderBalanceBefore = msgSender.balance;
        uint256 userBalanceBefore = user.balance;
        uint256 protocolBalanceBefore = address(this).balance;

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(friend));

        emit BuyShares(msgSender, user, amount, buyerPayment);

        friend.buyShares{value: buyerPayment + extraValue}(user, amount);

        (uint256 supply, uint256 price) = friend.users(user);

        assertEq(amount, supply);
        assertEq(newSpotPrice, price);
        assertEq(amount, friend.balanceOf(user, msgSender));
        assertEq(userBalanceBefore + userFee, user.balance);
        assertEq(protocolBalanceBefore + protocolFee, address(this).balance);
        assertEq(msgSenderBalanceBefore - buyerPayment, msgSender.balance);
    }
}
