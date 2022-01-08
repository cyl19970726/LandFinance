// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "./interface/IGovernor.sol";

/**
 * @dev Core of the governance system, designed to be extended though various modules.
 *
 * This contract is abstract and requires several function to be implemented in various modules:
 *
 * - A counting module must implement {quorum}, {_quorumReached}, {_voteSucceeded} and {_countVote}
 * - A voting module must implement {getVotes}
 * - Additionanly, the {votingPeriod} must also be implemented
 *
 * _Available since v4.3._
 */
abstract contract Governor is IGovernor , ERC165Upgradeable , ContextUpgradeable , EIP712Upgradeable{
    using TimersUpgradeable for TimersUpgradeable.BlockNumber;
    using SafeCastUpgradeable for uint256;
    using AddressUpgradeable for address;

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
 
    struct ProposalData{
        uint256 pid;
        uint8 status;
        address executorAddr;
        bytes4 selector;
        bytes params;
    }

    // 每个提案的投票有效期为3天
    // 一旦投票达到50%就会马上触发进入执行队列
    // 取消投票：
     struct ProposalCore {
        TimersUpgradeable.BlockNumber voteStart;
        TimersUpgradeable.BlockNumber voteEnd;
        bool executed;
        bool canceled;
    }

    mapping(uint256 => ProposalCore) private _proposals;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165Upgradeable, ERC165Upgradeable) returns (bool) {
        return interfaceId == type(IGovernor).interfaceId || super.supportsInterface(interfaceId);
    }

    function name() public pure virtual override returns (string memory){
        return "nft dao";
    }

    function version() public pure virtual override returns (string memory) {
        return "1";
    }

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure virtual override returns (uint256){
        return uint256(keccak256(abi.encode(targets,values,calldatas,descriptionHash)));
    }   

    function state(uint256 proposalId) public view virtual override returns(ProposalState){
        ProposalCore memory proposal = _proposals[proposalId];

        if (proposal.executed){
            return ProposalState.Executed;
        } else if (proposal.canceled){
            return ProposalState.Canceled;
        } else if (proposal.voteStart.isPending()) {
            // 还未开始vote
            return ProposalState.Pending;
        }else if (proposal.voteEnd.isPending()) {
            // 可以开始投票且vote还未结束
            return ProposalState.Active;
        }else if (proposal.voteEnd.isExpired()) {
            return _quorumReached(proposalId) && _voteSucceeded(proposalId)
                        ? ProposalState.Succeeded
                        : ProposalState.Defeated;
        }else{
            revert("Governor: unknown proposal id");
        }

    }


     /**
     * @dev See {IGovernor-proposalSnapshot}.
     */
    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteStart.getDeadline();
    }

    /**
     * @dev See {IGovernor-proposalDeadline}.
     */
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteEnd.getDeadline();
    }

    /**
     * @dev Amount of votes already cast passes the threshold limit.
     */
    function _quorumReached(uint256 proposalId) internal view virtual returns (bool);

    /**
     * @dev Is the proposal successful or not.
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual returns (bool);

    /**
     * @dev Register a vote with a given support and voting weight.
     *
     * Note: Support is generic and can represent various things depending on the voting system used.
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight
    ) internal virtual;

    /**
     * @dev See {IGovernor-propose}.
     */
    function propose(
        address[] memory targets ,
        uint256[] memory values ,
        bytes[] memory calldatas ,
        string memory description
    ) public virtual override returns(uint256){
        uint256 proposalId = hashProposal(targets, values , calldatas , keccak256(bytes(description)));

        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal");

        ProposalCore storage proposal = _proposals[proposalId];
        require(proposal.voteStart.isUnset(), "Governor: proposal already exists ");

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline =  snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);

        emit ProposalCreated(
            proposalId,
            _msgSender(),
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            deadline,
            description
        );

        return proposalId;
    }

    /**
     * @dev See {IGovernor-execute}.
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual override returns (uint256){
        uint256 proposalId = hashProposal(targets,values,calldatas,descriptionHash);
        
        // get proposal state
        ProposalState status = state(proposalId);
        require(
            status == ProposalState.Succeeded ||  status == ProposalState.Queued,
            "Governor: proposal not succeed"
        );

        //avoid Reentry attack
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        _execute(proposalId,targets,values,calldatas,descriptionHash);

        return proposalId;
    } 

    function _execute(
        uint256, /* proposalId */
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual{
        string memory errorMessage = "Governor: call reverted without message";
         for (uint256 i = 0; i < targets.length; ++i) {
            (bool success, bytes memory returndata) = targets[i].call{value: values[i]}(calldatas[i]);
            AddressUpgradeable.verifyCallResult(success, returndata, errorMessage);
        }
    }

    /**
     * @dev Internal cancel mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * canceled to allow distinguishing it from executed proposals.
     *
     * Emits a {IGovernor-ProposalCanceled} event.
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled && status != ProposalState.Expired && status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /**
     * @dev See {IGovernor-castVote}.
     */
    function castVote(uint256 proposalId, uint8 support) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "");
    }

    /**
     * @dev See {IGovernor-castVoteWithReason}.
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason);
    }

    /**
     * @dev See {IGovernor-castVoteBySig}.
     */
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        address voter = ECDSAUpgradeable.recover(
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support))),
            v,
            r,
            s
        );
        return _castVote(proposalId, voter, support, "");
    }

    function _cancle(
         address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual returns(uint256){
        uint256 proposalId = hashProposal(targets,values,calldatas,descriptionHash);
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled && status != ProposalState.Expired && status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        return proposalId;
    }


    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason
    ) internal virtual returns (uint256) {
        ProposalCore storage proposal = _proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        uint256 weight = getVotes(account, proposal.voteStart.getDeadline());
        _countVote(proposalId, account, support, weight);

        emit VoteCast(account, proposalId, support, weight, reason);

        return weight;
    }
    /**
     * @dev Address through which the governor executes action. Will be overloaded by module that execute actions
     * through another contract such as a timelock.
     */
    function _executor() internal view virtual returns (address) {
        return address(this);
    }
    



}