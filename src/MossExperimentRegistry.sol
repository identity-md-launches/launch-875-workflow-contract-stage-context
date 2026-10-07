// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice A public history of proposed and owner-approved experiments around one Moss token.
/// @dev This catalog never executes an experiment, modifies the token, or controls a pool.
///      Approval is an owner's endorsement, not a guarantee of an experiment's safety.
contract MossExperimentRegistry {
    enum Status {
        None,
        Pending,
        Active,
        Retired,
        Rejected
    }

    struct Proposal {
        bytes32 key;
        address implementation;
        bytes32 codeHash;
        bytes32 contentHash;
        address proposer;
        Status status;
    }

    /// @notice The sole token associated with this catalog; never replaced or transferred here.
    address public immutable token;
    /// @notice The explicit policy owner; factory deployment does not grant the factory this role.
    address public immutable owner;
    uint256 public proposalCount;
    mapping(uint256 proposalId => Proposal) private _proposals;
    /// @notice Last approved, unretired proposal for a key. Use isActive to also check current code.
    mapping(bytes32 key => uint256 proposalId) public activeProposal;

    error Unauthorized();
    error InvalidOwner();
    error InvalidToken();
    error EmptyHash();
    error InvalidImplementation();
    error UnknownProposal(uint256 proposalId);
    error InvalidStatus(uint256 proposalId, Status status);
    error StaleActiveProposal(uint256 expected, uint256 actual);
    error ImplementationChanged(uint256 proposalId);
    error NoActiveProposal(bytes32 key);

    event ExperimentProposed(
        uint256 indexed proposalId,
        bytes32 indexed key,
        address indexed proposer,
        address implementation,
        bytes32 codeHash,
        bytes32 contentHash
    );
    event ExperimentApproved(
        uint256 indexed proposalId, bytes32 indexed key, uint256 previousProposalId, bytes32 decisionHash
    );
    event ExperimentRetired(uint256 indexed proposalId, bytes32 indexed key, bytes32 decisionHash);
    event ExperimentRejected(uint256 indexed proposalId, bytes32 indexed key, bytes32 decisionHash);

    /// @param token_ The already deployed LaunchToken, supplied as $token by the manifest.
    /// @param owner_ The policy owner, supplied as $owner, preferably a reviewed multisig.
    constructor(address token_, address owner_) {
        if (token_ == address(0) || token_.code.length == 0) revert InvalidToken();
        if (owner_ == address(0) || owner_ == address(this) || owner_ == token_ || owner_ == msg.sender) {
            revert InvalidOwner();
        }
        token = token_;
        owner = owner_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /// @notice Anyone, including an offchain AI operator, can propose a deployed experiment.
    /// @param key A stable, nonzero experiment identifier; different keys can be active together.
    /// @param implementation The contract that users would opt into independently.
    /// @param contentHash keccak256 of the exact UTF-8 journal document describing this version.
    /// @dev Neither the token nor this registry can itself be an experiment. Proposal contents are immutable.
    function propose(bytes32 key, address implementation, bytes32 contentHash) external returns (uint256 proposalId) {
        if (key == bytes32(0) || contentHash == bytes32(0)) revert EmptyHash();
        if (implementation == token || implementation == address(this) || implementation.code.length == 0) {
            revert InvalidImplementation();
        }

        proposalId = ++proposalCount;
        bytes32 codeHash = implementation.codehash;
        _proposals[proposalId] = Proposal(key, implementation, codeHash, contentHash, msg.sender, Status.Pending);
        emit ExperimentProposed(proposalId, key, msg.sender, implementation, codeHash, contentHash);
    }

    /// @notice Endorse a pending version and retire any previously approved version of its key.
    /// @param expectedActiveId The active id observed when reviewing, or zero for no active version.
    /// @param decisionHash keccak256 of the published review/decision document.
    /// @dev A stale approval reverts. Only direct runtime bytes are checked; proxies and dependencies
    ///      need separate review. No code from the proposed implementation is called.
    function approve(uint256 proposalId, uint256 expectedActiveId, bytes32 decisionHash) external onlyOwner {
        if (decisionHash == bytes32(0)) revert EmptyHash();
        Proposal storage proposal = _getProposal(proposalId);
        if (proposal.status != Status.Pending) revert InvalidStatus(proposalId, proposal.status);
        uint256 previousId = activeProposal[proposal.key];
        if (expectedActiveId != previousId) revert StaleActiveProposal(expectedActiveId, previousId);
        if (!_codeMatches(proposal)) revert ImplementationChanged(proposalId);

        if (previousId != 0) {
            _proposals[previousId].status = Status.Retired;
            emit ExperimentRetired(previousId, proposal.key, decisionHash);
        }
        proposal.status = Status.Active;
        activeProposal[proposal.key] = proposalId;
        emit ExperimentApproved(proposalId, proposal.key, previousId, decisionHash);
    }

    /// @notice Reject a pending proposal without affecting any active version.
    function reject(uint256 proposalId, bytes32 decisionHash) external onlyOwner {
        if (decisionHash == bytes32(0)) revert EmptyHash();
        Proposal storage proposal = _getProposal(proposalId);
        if (proposal.status != Status.Pending) revert InvalidStatus(proposalId, proposal.status);
        proposal.status = Status.Rejected;
        emit ExperimentRejected(proposalId, proposal.key, decisionHash);
    }

    /// @notice Withdraw an endorsement, retaining the proposal and its history permanently.
    /// @dev Retirement cannot stop or recover funds from an independently used experiment.
    function retire(bytes32 key, uint256 expectedActiveId, bytes32 decisionHash) external onlyOwner {
        if (decisionHash == bytes32(0)) revert EmptyHash();
        uint256 proposalId = activeProposal[key];
        if (proposalId == 0) revert NoActiveProposal(key);
        if (expectedActiveId != proposalId) revert StaleActiveProposal(expectedActiveId, proposalId);
        _proposals[proposalId].status = Status.Retired;
        delete activeProposal[key];
        emit ExperimentRetired(proposalId, key, decisionHash);
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return _getProposal(proposalId);
    }

    /// @notice True only for a currently endorsed proposal whose direct runtime bytes still match.
    /// @dev False for unknown ids. Does not prove safety or detect changes behind proxies.
    function isActive(uint256 proposalId) external view returns (bool) {
        Proposal storage proposal = _proposals[proposalId];
        return proposal.status == Status.Active && activeProposal[proposal.key] == proposalId && _codeMatches(proposal);
    }

    function _getProposal(uint256 proposalId) private view returns (Proposal storage proposal) {
        if (proposalId == 0 || proposalId > proposalCount) revert UnknownProposal(proposalId);
        return _proposals[proposalId];
    }

    function _codeMatches(Proposal storage proposal) private view returns (bool) {
        return proposal.implementation.code.length > 0 && proposal.implementation.codehash == proposal.codeHash;
    }
}
