// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ExponentialCurve} from "sudoswap/bonding-curves/ExponentialCurve.sol";
import "src/FriendShares.sol";

contract FriendSharesTest is Test, ExponentialCurve {
    uint256 private constant REGISTRATION_FEE = 0.05 ether;
    uint256 private constant PROTOCOL_FEE_PERCENT = 1e16;
    uint256 private constant USER_FEE_PERCENT = 4e16;
    uint256 private constant INITIAL_PRICE = 0.001 ether;
    uint128 private constant EXPONENTIAL_CURVE_DELTA = 1e18 + 1e14;
    FriendShares public immutable friend = new FriendShares(address(this));

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

    receive() external payable {}

    function _calculateSharesBuyPrice(
        string memory user,
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
        uint256 spotPrice = friend.sharesPrice(user);

        if (spotPrice == 0) spotPrice = INITIAL_PRICE;

        (, newSpotPrice, , buyerPayment, userFee, protocolFee) = getBuyInfo(
            uint128(spotPrice),
            EXPONENTIAL_CURVE_DELTA,
            amount,
            USER_FEE_PERCENT,
            PROTOCOL_FEE_PERCENT
        );
    }

    function testCannotRegisterUser_AlreadyRegistered() external {
        string memory user = "kp";
        address wallet = address(this);

        friend.registerUser{value: REGISTRATION_FEE}(user, wallet);

        vm.expectRevert(FriendShares.AlreadyRegistered.selector);

        friend.registerUser{value: REGISTRATION_FEE}(user, wallet);
    }

    function testCannotRegisterUser_InvalidUser() external {
        string memory user = "";
        address wallet = address(this);

        vm.expectRevert(FriendShares.InvalidUser.selector);

        friend.registerUser{value: REGISTRATION_FEE}(user, wallet);
    }

    function testCannotRegisterUser_InvalidWallet() external {
        string memory user = "kp";
        address wallet = address(0);

        vm.expectRevert(FriendShares.InvalidWallet.selector);

        friend.registerUser{value: REGISTRATION_FEE}(user, wallet);
    }

    function testCannotRegisterUser_InsufficientPayment(
        uint256 value
    ) external {
        vm.assume(value < REGISTRATION_FEE);

        string memory user = "kp";
        address wallet = address(this);

        vm.expectRevert(FriendShares.InsufficientPayment.selector);

        friend.registerUser{value: value}(user, wallet);
    }

    function testRegisterUser() external {
        address msgSender = address(1);
        string memory user = "kp";
        address wallet = address(1);
        uint256 ownerBalanceBefore = address(this).balance;

        vm.deal(msgSender, REGISTRATION_FEE);
        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(friend));

        emit RegisterUser(user, wallet);

        friend.registerUser{value: REGISTRATION_FEE}(user, wallet);

        assertEq(ownerBalanceBefore + REGISTRATION_FEE, address(this).balance);
        assertEq(wallet, friend.users(user));
    }

    /*//////////////////////////////////////////////////////////////
                             buyShares
    //////////////////////////////////////////////////////////////*/

    function testCannotBuyShares_InvalidUser() external {
        string memory user = "kp";
        uint256 amount = 1;

        assertEq(address(0), friend.users(user));

        vm.expectRevert(FriendShares.InvalidUser.selector);

        friend.buyShares{value: INITIAL_PRICE}(user, amount);
    }

    function testCannotBuyShares_InsufficientPayment() external {
        string memory user = "kp";
        address wallet = address(this);
        uint256 amount = 1;

        friend.registerUser{value: REGISTRATION_FEE}(user, wallet);

        vm.expectRevert(FriendShares.InsufficientPayment.selector);

        friend.buyShares{value: 0}(user, amount);
    }

    function testBuyShares() external {
        address msgSender = address(1);
        string memory user = "kp";
        address wallet = address(2);
        uint256 amount = 1;

        friend.registerUser{value: REGISTRATION_FEE}(user, wallet);

        (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        ) = _calculateSharesBuyPrice(user, amount);
        uint256 userBalanceBefore = wallet.balance;
        uint256 protocolBalanceBefore = address(this).balance;

        assertEq(0, friend.sharesSupply(user));
        assertEq(0, friend.sharesBalance(user, msgSender));
        assertEq(0, friend.sharesPrice(user));

        vm.deal(msgSender, buyerPayment);
        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(friend));

        emit BuyShares(msgSender, user, amount, buyerPayment);

        friend.buyShares{value: buyerPayment}(user, amount);

        assertEq(amount, friend.sharesSupply(user));
        assertEq(amount, friend.sharesBalance(user, msgSender));
        assertEq(newSpotPrice, friend.sharesPrice(user));
        assertEq(userBalanceBefore + userFee, wallet.balance);
        assertEq(protocolBalanceBefore + protocolFee, address(this).balance);
    }

    function testBuySharesFuzz(
        string memory user,
        uint16 amount,
        uint16 extraValue
    ) external {
        vm.assume(bytes(user).length != 0);
        vm.assume(amount != 0);

        address msgSender = address(1);
        address wallet = address(2);

        friend.registerUser{value: REGISTRATION_FEE}(user, wallet);

        (
            uint128 newSpotPrice,
            uint256 buyerPayment,
            uint256 userFee,
            uint256 protocolFee
        ) = _calculateSharesBuyPrice(user, amount);

        vm.deal(msgSender, buyerPayment + extraValue);

        uint256 msgSenderBalanceBefore = msgSender.balance;
        uint256 userBalanceBefore = wallet.balance;
        uint256 protocolBalanceBefore = address(this).balance;

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(friend));

        emit BuyShares(msgSender, user, amount, buyerPayment);

        friend.buyShares{value: buyerPayment + extraValue}(user, amount);

        assertEq(amount, friend.sharesSupply(user));
        assertEq(amount, friend.sharesBalance(user, msgSender));
        assertEq(newSpotPrice, friend.sharesPrice(user));
        assertEq(userBalanceBefore + userFee, wallet.balance);
        assertEq(protocolBalanceBefore + protocolFee, address(this).balance);
        assertEq(msgSenderBalanceBefore - buyerPayment, msgSender.balance);
    }
}
