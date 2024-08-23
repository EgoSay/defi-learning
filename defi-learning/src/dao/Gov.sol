// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import  "./Types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// copy from https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/GovernorAlpha.sol
contract Gov is EIP712 {

    // the voting token is the token that will be used to vote on proposals
    address public votingToken;
    /// @notice The address of the Governor Guardian
    address public guardian;
    /// @notice The address of the Compound Protocol Timelock
    TimelockInterface public timelock;


    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support,address voter)");

    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public pure returns (uint) { return 400000e18; } // 400,000 = 4% of Comp

    /// @notice The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public pure returns (uint) { return 100000e18; } // 100,000 = 1% of Comp

    /// @notice The maximum number of actions that can be included in a proposal
    function proposalMaxOperations() public pure returns (uint) { return 10; } // 10 actions

    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure returns (uint) { return 1; } // 1 block

    /// @notice The duration of voting on a proposal, in blocks
    function votingPeriod() virtual public pure returns (uint) { return 17280; } // ~3 days in blocks (assuming 15s blocks)

    /// @notice The total number of proposals
    uint public proposalCount;

    /// @notice The official record of all proposals ever proposed
    mapping (uint => Types.Proposal) public proposals;

    /// @notice The latest proposal for each proposer
    mapping (address => uint) public latestProposalIds;

    string public name;
    

    constructor(address _votingToken, address _guardian, address timelock_, string memory name_) EIP712(name_, "1") {
        votingToken = _votingToken;
        guardian = _guardian;
        timelock = TimelockInterface(timelock_);
        name = name_;
    }

    // create a proposal
    function createProposal(address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) public returns (uint proposalId) {
        require(targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length, "GovernorAlpha::propose: proposal function information arity mismatch");
        require(targets.length != 0, "GovernorAlpha::propose: must provide actions");
        require(targets.length <= proposalMaxOperations(), "GovernorAlpha::propose: too many actions");
        uint256 pastVotes = IVotingToken(votingToken).getPastVotes(msg.sender, sub256(block.number, 1));
        require(pastVotes < proposalMaxOperations(), "GovernorAlpha::propose: proposer votes below proposal threshold");

        uint latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
            Types.ProposalState lastProposalState = state(proposalId);
            require(lastProposalState != Types.ProposalState.Active, "GovernorAlpha::propose: one live proposal per proposer, found an already active proposal");
            require(lastProposalState != Types.ProposalState.Pending, "GovernorAlpha::propose: one live proposal per proposer, found an already pending proposal");
        }

        uint startBlock = add256(block.number, votingDelay());
        uint endBlock = add256(startBlock, votingPeriod());
        proposalId = proposalCount++;

        // the Proposal struct contains mapping, so have to use the following way to initialize
        Types.Proposal storage newProposal = proposals[proposalId];
        // This should never happen but add a check in case.
        require(newProposal.id == 0, "GovernorAlpha::propose: ProposalID collsion");
        newProposal.id = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.eta = 0;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.signatures = signatures;
        newProposal.calldatas = calldatas;
        newProposal.startBlock = startBlock;
        newProposal.endBlock = endBlock;
        newProposal.forVotes = 0;
        newProposal.againstVotes = 0;
        newProposal.canceled = false;
        newProposal.executed = false;

        latestProposalIds[newProposal.proposer] = newProposal.id;
        emit ProposalCreated(newProposal.id, msg.sender, targets, values, signatures, calldatas, startBlock, endBlock, description);
        return newProposal.id;
    }


    // cancel proposal
    function cancelProposal(uint proposalId) public {
        require(msg.sender == guardian, "GovernorAlpha::cancel: sender must be guardian");
        Types.Proposal storage proposal = proposals[proposalId];
        require(state(proposalId) == Types.ProposalState.Active, "GovernorAlpha::cancel: proposal not active");
        proposal.canceled = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalCanceled(proposalId);
    }


    function castVote(uint proposalId, bool support) public {
        return _castVote(msg.sender, proposalId, support);
    }

    /**
     * @dev Cast a vote using the voter's signature, including ERC-1271 signature support.
     *
     * Emits a {VoteCast} event.
     */
    function castVoteBySig(uint proposalId, bool support, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support, address(this)));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, v, r, s);
        require(signer != address(0), "GovernorAlpha::castVoteBySig: invalid signature");
        return _castVote(signer, proposalId, support);
    }
    function _castVote(address voter, uint proposalId, bool support) internal {
        // user cast votes
        require(state(proposalId) == Types.ProposalState.Active, "GovernorAlpha::_castVote: voting is closed");

        Types.Proposal storage proposal = proposals[proposalId];
        Types.Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasVoted == false, "GovernorAlpha::_castVote: voter already voted");

        uint256 votes = IVotingToken(votingToken).getPastVotes(voter, proposal.startBlock);

        if (support) {
            proposal.forVotes = add256(proposal.forVotes, votes);
        } else {
            proposal.againstVotes = add256(proposal.againstVotes, votes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, support, votes);
    }

    
    function state(uint proposalId) public view returns (Types.ProposalState) {
        // custom define proposal state
        require(proposalCount >= proposalId && proposalId > 0, "GovernorAlpha::state: invalid proposal id");
        Types.Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return Types.ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return Types.ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return Types.ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes()) {
            return Types.ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return Types.ProposalState.Succeeded;
        } else if (proposal.executed) {
            return Types.ProposalState.Executed;
        } else if (block.timestamp >= add256(proposal.eta, timelock.GRACE_PERIOD())) {
            return Types.ProposalState.Expired;
        } else {
            return Types.ProposalState.Queued;
        }
    }


    // if proposal is successful, queue it for execution
    function queue(uint proposalId) public {
        require(state(proposalId) == Types.ProposalState.Succeeded, "GovernorAlpha::queue: proposal can only be queued if it is succeeded");
        Types.Proposal storage proposal = proposals[proposalId];
        uint eta = add256(block.timestamp, timelock.delay());
        for (uint i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], eta);
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }
    function _queueOrRevert(address target, uint value, string memory signature, bytes memory data, uint eta) internal {
        require(!timelock.queuedTransactions(keccak256(abi.encode(target, value, signature, data, eta))), "GovernorAlpha::_queueOrRevert: proposal action already queued at eta");
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    function execute(uint proposalId) public payable {
        // execute proposal
        require(state(proposalId) == Types.ProposalState.Queued, "GovernorAlpha::execute: proposal can only be executed if it is queued");
        Types.Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction{value: proposal.values[i]}(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalExecuted(proposalId);
    }

    function getChainId() internal view returns (uint) {
        uint chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    function sub256(uint256 a, uint256 b) internal pure returns (uint) {
        require(b <= a, "subtraction underflow");
        return a - b;
    }

    function add256(uint256 a, uint256 b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }
    


    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(uint id, address proposer, address[] targets, uint[] values, string[] signatures, bytes[] calldatas, uint startBlock, uint endBlock, string description);

    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(address voter, uint proposalId, bool support, uint votes);

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint id);

    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint id, uint eta);

    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint id);

}

interface TimelockInterface {
    function delay() external view returns (uint);
    function GRACE_PERIOD() external view returns (uint);
    function acceptAdmin() external;
    function queuedTransactions(bytes32 hash) external view returns (bool);
    function queueTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external returns (bytes32);
    function cancelTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external;
    function executeTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external payable returns (bytes memory);
}

interface IVotingToken {
    /**
     * @dev Returns the current amount of votes that `account` has.
     */
    function getVotes(address account) external view returns (uint96);

    /**
     * @dev Returns the amount of votes that `account` had at a specific moment in the past. If the `clock()` is
     * configured to use block numbers, this will return the value at the end of the corresponding block.
     */
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);

    /**
     * @dev Returns the total supply of votes available at a specific moment in the past. If the `clock()` is
     * configured to use block numbers, this will return the value at the end of the corresponding block.
     *
     * NOTE: This value is the sum of all available votes, which is not necessarily the sum of all delegated votes.
     * Votes that have not been delegated are still part of total supply, even though they would not participate in a
     * vote.
     */
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);

    /**
     * @dev Returns the delegate that `account` has chosen.
     */
    function delegates(address account) external view returns (address);

    /**
     * @dev Delegates votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) external;

    /**
     * @dev Delegates votes from signer to `delegatee`.
     */
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;
}

