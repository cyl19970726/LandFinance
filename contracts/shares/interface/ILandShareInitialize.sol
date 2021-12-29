// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILandShareInitialize{
    function Initialize(string memory name, string memory symbol , address NFTAddr , address NFTOwner , uint256 NFTId , uint256 sharesCap , uint256 sharesPublish , uint256 perSharePrice) external;
}