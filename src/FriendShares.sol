// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {XykCurve} from "sudoswap/bonding-curves/XykCurve.sol";

contract FriendShares is Ownable, XykCurve {
    using SafeTransferLib for address;

    uint256 public constant PROTOCOL_FEE_PERCENT = 100;
    uint256 public constant SUBJECT_FEE_PERCENT = 400;
    uint256 public constant FEE_PERCENT_BASE = 10_000;

    event Trade(
        address trader,
        address subject,
        bool isBuy,
        uint256 shareAmount,
        uint256 ethAmount,
        uint256 protocolEthAmount,
        uint256 subjectEthAmount,
        uint256 supply
    );

    // SharesSubject => (Holder => Balance)
    mapping(address => mapping(address => uint256)) public sharesBalance;

    // SharesSubject => Supply
    mapping(address => uint256) public sharesSupply;

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

    function getBuyPrice(address sharesSubject, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[sharesSubject], amount);
    }

    function getSellPrice(address sharesSubject, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[sharesSubject] - amount, amount);
    }

    function getBuyPriceAfterFee(address sharesSubject, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(sharesSubject, amount);
        uint256 protocolFee = price * PROTOCOL_FEE_PERCENT / FEE_PERCENT_BASE;
        uint256 subjectFee = price * SUBJECT_FEE_PERCENT / FEE_PERCENT_BASE;
        return price + protocolFee + subjectFee;
    }

    function getSellPriceAfterFee(address sharesSubject, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(sharesSubject, amount);
        uint256 protocolFee = price * PROTOCOL_FEE_PERCENT / FEE_PERCENT_BASE;
        uint256 subjectFee = price * SUBJECT_FEE_PERCENT / FEE_PERCENT_BASE;
        return price - protocolFee - subjectFee;
    }

    function buyShares(address sharesSubject, uint256 amount) public payable {
        uint256 supply = sharesSupply[sharesSubject];
        require(supply > 0 || sharesSubject == msg.sender, "Only the shares' subject can buy the first share");
        uint256 price = getPrice(supply, amount);
        uint256 protocolFee = price * PROTOCOL_FEE_PERCENT / FEE_PERCENT_BASE;
        uint256 subjectFee = price * SUBJECT_FEE_PERCENT / FEE_PERCENT_BASE;
        require(msg.value >= price + protocolFee + subjectFee, "Insufficient payment");
        sharesBalance[sharesSubject][msg.sender] = sharesBalance[sharesSubject][msg.sender] + amount;
        sharesSupply[sharesSubject] = supply + amount;
        emit Trade(msg.sender, sharesSubject, true, amount, price, protocolFee, subjectFee, supply + amount);

        // Distribute ETH fees.
        owner().safeTransferETH(protocolFee);
        sharesSubject.safeTransferETH(subjectFee);
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
