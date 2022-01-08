// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./GovernorCompatibility.sol";

contract GovernorCore is GovernorCompatibility{


    constructor(){

    }

    // override IGovernorTimeLock
    function timeDelayedExecute() public view virtual override returns(uint256){
        return 1000;
    }

    // @ dev 需要持有多少股权才能创建提案
    function proposalThreshold() public view virtual override returns (uint256){
        return 100;
    }


    // 提案可以通过的最小投票数量
    function quorum(uint256 blockNumber) public view virtual override returns (uint256){

    }

    function getVotes(address account, uint256 blockNumber) public view virtual override returns (uint256){

    }

    function hasVoted(uint256 proposalId, address account) public view virtual override returns (bool){

    }

     // 投票周期
    function votingPeriod() public view virtual override returns (uint256){
        
    }


    // have override by GovernorCompatibility
    /**
     * @dev Amount of votes already cast passes the threshold limit.
     */
    function _quorumReached(uint256 proposalId) internal view virtual override returns (bool){}

    /**
     * @dev Is the proposal successful or not.
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool){}

   

}