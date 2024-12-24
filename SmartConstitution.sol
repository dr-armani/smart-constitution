// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum Phase {
    Registration, // Days 1-14: Candidate and voter registration
    Election, // 1 Day: Voting for the transitional government
    Governance, // 10 weeks: Collecting constitution drafts
    Referendum, // 1 Day: Referendum day
    Ratification // New Constitution Ratified
}
struct Candidate {
    string fullName;
    string bio;
    string website;
    uint256 registeredAt;
    uint256 voteCount;
    bool electedMember; // true if they became one of the 50 members
    uint256 leaderAt; // 0 if never led, otherwise the week number they led
}
struct Payment {
    uint256 amount;
    address recipient;
    string reason;
}
struct Proposal {
    address proposer;
    string provisions;
    uint256 proposedAt;
    uint256 executedAt;
    uint256 withdrawnAt;
    uint8 yesVotes;
    Payment[] payments;
    //mapping(address => uint256) memberVotedAt;
}

contract SharedStorage {
    uint32 public constant RANDOM_VOTERS = 1200; // 1200 random voters
    uint256 public constant REG_TIME = 2 weeks;
    uint8 public constant N_MEMBERS = 50;
    uint256 public immutable startTime;
    uint256 public electionEnd;
    address public neutral; // Address of the international oversight agent to find random voters
    uint32 public addedVoterCount;
    address[] public candidateList;
    mapping(address => Candidate) public candidateInfo;

    Proposal[] public proposals; // proposals[0] is this transitional constitution.
    uint256 public referendumEndTime;

    function getCurrentPhase() public returns (Phase) {
        if (block.timestamp < electionEnd - 1 days) return Phase.Registration;
        else if (block.timestamp < electionEnd)
            if (
                candidateList.length < 2 * N_MEMBERS ||
                addedVoterCount < RANDOM_VOTERS
            ) {
                // Postpone election for two weeks if fewer than 100 candidates or fewer than 1200 voters
                electionEnd = electionEnd + REG_TIME;
                return Phase.Registration;
            } else return Phase.Election;
        else if (referendumEndTime == 0) return Phase.Governance;
        else if (block.timestamp < referendumEndTime) return Phase.Referendum;
        else return Phase.Ratification;
        // else return Phase.Restart
    }
}

contract Formation is SharedStorage {
    uint256 public constant LEAD_PERIOD = 1 weeks;
    uint256 public constant REG_FEE = 1 ether / 1000;
    uint32 public constant VOTER_BATCH = 10;

    mapping(bytes32 => bool) private isVoterHash; // Random voter hash
    mapping(address => uint256) private voteTime; // 0:not registered, 1:registered, >1:voted at timestamp

    address[N_MEMBERS] public electedMembers;
    bool public membersElected = false;

    address public currentLeaderAddress;
    uint256 public currentLeaderNumber; // Member number of the Current Leader
    
    /**
    * @notice Neutral: Verify that (1957 <= yearOfBirth <= 2006).   
    * @param voterAddresses: Wallet addresses of the randomly selected voters 
    * @param voterHashes: Hash of yearOfBirth(yyyy)+monthOfBirth(mm)+gender(male=0,female=1) 
    * @notice Neutral: Calculate hash offchain in frontend: 

    Example JavaScript Code: 
    const crypto = require('crypto'); 
    const yearOfBirth = 1995; // Before 2006 
    const monthOfBirth = 6; // June
    const gender = 1; // Female
    if (yearOfBirth > 2006) { 
        throw new Error("Must be born in or before 2006"); } 
    const input = String(yearOfBirth) + String(monthOfBirth).padStart(2, '0') + String(gender);
    console.log(input); // "2006061"
    const hash = crypto.createHash('sha256').update(input).digest('hex'); 
    console.log("Hash:", hash);
    */

    function addVoter(
        address[VOTER_BATCH] calldata voterAddresses, // 10 voters' addresses in a random order
        bytes32[VOTER_BATCH] calldata voterHashes // 10 voters' hashes in a random order 
    ) external { 
        require(msg.sender == neutral, "Not authorized neutral");
        require(
            getCurrentPhase() == Phase.Registration,
            "Voter adding period has ended."
        );
        require(
            addedVoterCount < RANDOM_VOTERS,
            "Maximum number of voters reached."
        );
        require(
            voterHashes.length == VOTER_BATCH &&
                voterAddresses.length == VOTER_BATCH,
            "Incorrect batch size"
        );

        // Check all hashes are new
        for (uint8 i = 0; i < VOTER_BATCH; i++) {
            require(
                !isVoterHash[voterHashes[i]],
                "Voter hash already registered"
            );
            isVoterHash[voterHashes[i]] = true;
        }

        // Enable voting for all addresses
        for (uint8 i = 0; i < VOTER_BATCH; i++) {
            require(voterAddresses[i] != address(0), "Invalid voter address");
            require(
                voteTime[voterAddresses[i]] == 0,
                "Addresss already registered. Registrar ERROR!"
            );
            voteTime[voterAddresses[i]] = 1;
        }

        addedVoterCount += VOTER_BATCH;

        emit VoterAdded(voterAddresses, addedVoterCount);
    }
    event VoterAdded(
        address[VOTER_BATCH] indexed voter,
        uint256 addedVoterCount
    );

    function getHashStatus(bytes32 voterHash) external view returns (bool) {
        return isVoterHash[voterHash];
    }

    function getVoteTime(address voterAddress) external view returns (uint256) {
        return voteTime[voterAddress];
    }

    /**
     * @notice Register as a candidate with required information
     * @param _fullName Candidate's full name
     * @param _bio Brief biography of the candidate
     * @param _website Additional relevant information (education, experience, etc.)
     */

    function registerAsCandidate(
        string memory _fullName,
        string memory _bio,
        string memory _website
    ) external payable {
        require(
            bytes(_fullName).length > 0 && bytes(_fullName).length <= 100,
            "Invalid name"
        );
        require(
            bytes(_bio).length > 0 && bytes(_bio).length <= 1000,
            "Invalid bio"
        );
        require(
            bytes(_website).length > 0 && bytes(_website).length <= 1000,
            "Invalid website"
        );
        require(msg.sender != address(0), "Invalid sender");
        require(msg.value >= REG_FEE, "Insufficient registration fee");
        require(
            getCurrentPhase() == Phase.Registration,
            "Candidate registration period has ended."
        );
        require(
            candidateInfo[msg.sender].registeredAt == 0,
            "Already registered"
        );
        candidateInfo[msg.sender] = Candidate({
            fullName: _fullName,
            bio: _bio,
            website: _website,
            registeredAt: block.timestamp,
            voteCount: 0,
            electedMember: false,
            leaderAt: 0
        });

        candidateList.push(msg.sender);
        emit CandidateRegistered(msg.sender, _fullName, _bio, _website);
    }
    event CandidateRegistered(
        address indexed candidate,
        string fullName,
        string bio,
        string website
    );

    function getCandidateInfo(
        uint256 candidateID
    ) external view returns (Candidate memory) {
        require(candidateID < candidateList.length, "Invalid Candidate ID");
        return candidateInfo[candidateList[candidateID]];
    }

    //mapping(address => uint256[]) private voter2Candidates;
    function voteCandidates(uint256[] calldata _candidatesIds) external {
        require(getCurrentPhase() == Phase.Election, "Not in Election phase");
        require(
            _candidatesIds.length <= candidateList.length,
            "Invalid vote count"
        );
        require(
            voteTime[msg.sender] == 1,
            "Already voted (>1) or not registered (0)"
        );

        bool[] memory votedFor = new bool[](candidateList.length);

        voteTime[msg.sender] = block.timestamp;
        emit VoteCast(msg.sender);

        for (uint256 i = 0; i < _candidatesIds.length; i++) {
            uint256 _candidateId = _candidatesIds[i];
            require(
                _candidateId < candidateList.length,
                "Wrong candidate index"
            );
            require(!votedFor[_candidateId], "Repetitive candidate index");
            votedFor[_candidateId] = true;
            candidateInfo[candidateList[_candidateId]].voteCount++;
            // voter2Candidates[msg.sender].push(_candidateId);
        }
    }
    event VoteCast(address indexed voter);

    function getElectionResults() external returns (address[N_MEMBERS] memory) {
        if (membersElected) {
            return electedMembers;
        }
        require(block.timestamp > electionEnd, "Call after election");
        unchecked {
            for (uint256 i = 1; i <= N_MEMBERS; i++) {
                for (uint256 j = 0; j < candidateList.length - i; j++) {
                    if (
                        candidateInfo[candidateList[j]].voteCount >
                        candidateInfo[candidateList[j + 1]].voteCount
                    ) {
                        (candidateList[j], candidateList[j + 1]) = (
                            candidateList[j + 1],
                            candidateList[j]
                        );
                    }
                }
                electedMembers[i - 1] = candidateList[candidateList.length - i];
                candidateInfo[candidateList[candidateList.length - i]]
                    .electedMember = true;
            }
        }

        membersElected = true;

        currentLeaderAddress = electedMembers[0]; // = candidateList[candidateList.length - 1] ; Highest voted candidate
        currentLeaderNumber = 0;

        candidateInfo[currentLeaderAddress].leaderAt = block.timestamp;

        emit ElectionResults(electedMembers, currentLeaderAddress);
        return electedMembers;
    }
    event ElectionResults(
        address[N_MEMBERS] indexed electedMembers,
        address firstLeader
    );

    function changeLeader() external {
        require(membersElected, "No leader yet");
        require(
            block.timestamp >=
                candidateInfo[currentLeaderAddress].leaderAt + LEAD_PERIOD,
            "Current leader's term not finished"
        );

        currentLeaderNumber++;

        if (currentLeaderNumber >= electedMembers.length)
            currentLeaderNumber = 0;

        currentLeaderAddress = electedMembers[currentLeaderNumber];

        candidateInfo[currentLeaderAddress].leaderAt = block.timestamp;
        emit LeadershipChanged(currentLeaderAddress);
    }
    event LeadershipChanged(address indexed newLeader);
}

contract Governance is SharedStorage {
    uint8 public constant SUPER_MAJORITY = 30;

    mapping(address => uint256) public activeProposalByMember; // 0 if no active proposal, otherwise proposalId
    mapping(address => mapping(uint256 => uint256)) public memberVotedAt;

    function proposeProposal(
        string calldata _provisions,
        Payment[] calldata _payments
    ) external returns (uint256) {
        require(
            candidateInfo[msg.sender].electedMember,
            "Only members can propose proposals"
        );
        require(bytes(_provisions).length > 0, "Provisions required");
        require(
            activeProposalByMember[msg.sender] == 0,
            "Member already has an active proposal"
        );

        uint256 proposalId = proposals.length;
        activeProposalByMember[msg.sender] = proposalId;

        proposals.push(); // Push empty proposal first
        Proposal storage newProposal = proposals[proposalId];

        newProposal.proposer = msg.sender;
        newProposal.provisions = _provisions;
        newProposal.proposedAt = block.timestamp;
        // Copy payments array
        for (uint256 i = 0; i < _payments.length; i++) {
            newProposal.payments.push(_payments[i]);
        }

        emit ProposalProposed(proposals.length, msg.sender, _provisions);
        return proposals.length;
    }
    event ProposalProposed(
        uint256 indexed proposalId,
        address indexed proposer,
        string provisions
    );

    function voteForProposal(uint256 proposalId) external returns (uint8) {
        require(
            candidateInfo[msg.sender].electedMember,
            "Only members can vote"
        );
        require(proposalId < proposals.length, "Invalid proposal ID");

        Proposal storage proposal = proposals[proposalId];
        require(proposal.withdrawnAt == 0, "Proposal withdrawn");
        //require(proposal.memberVotedAt[msg.sender]==0, "Already voted");
        //proposal.memberVotedAt[msg.sender] = block.timestamp;

        require(memberVotedAt[msg.sender][proposalId] == 0, "Already voted");
        memberVotedAt[msg.sender][proposalId] = block.timestamp;

        proposal.yesVotes++;

        emit ProposalVoted(proposalId, msg.sender);

        if (proposal.yesVotes >= SUPER_MAJORITY && proposal.executedAt == 0) {
            emit ProposalPassed(proposalId);
            proposal.executedAt = block.timestamp;
            activeProposalByMember[proposal.proposer] = 0;
            _executeProposal(proposalId);
        }

        return proposal.yesVotes;
    }
    event ProposalVoted(uint256 indexed proposalId, address indexed voter);
    event ProposalPassed(uint256 indexed proposalId);

    function withdrawProposal(uint256 proposalId) external {
        require(proposalId < proposals.length, "Invalid proposal ID");
        Proposal storage proposal = proposals[proposalId];
        require(
            proposal.proposer == msg.sender,
            "Only the proposer can withdraw"
        );
        require(proposal.executedAt == 0, "Proposal already executed");
        require(proposal.withdrawnAt == 0, "Proposal already withdrawn");

        proposal.withdrawnAt = block.timestamp;
        activeProposalByMember[msg.sender] = 0;

        emit ProposalWithdrawn(proposalId);
    }
    event ProposalWithdrawn(uint256 indexed proposalId);

    function _executeProposal(uint256 proposalId) private {
        Proposal storage proposal = proposals[proposalId];
        for (uint256 i; i < proposal.payments.length; i++) {
            Payment memory payment = proposal.payments[i];
            payable(payment.recipient).transfer(payment.amount);
        }
    }

    function getProposalInfo(
        uint256 proposalId
    ) external view returns (Proposal memory) {
        require(proposalId < proposals.length, "Invalid proposal ID");
        return proposals[proposalId];
    }
}

contract Finance is SharedStorage {
    uint8 constant MEDIAN_MEMBER = uint8(N_MEMBERS / 2);

    uint256 public currentRate;
    struct InterestPeriod {
        uint256 rate; // Interest rate in basis points
        uint256 startedAt; // When this rate becomes effective
    }
    InterestPeriod[] public interestPeriods;

    struct Txn {
        int256 amount;
        uint256 txnTime;
    }
    mapping(address => Txn[]) public LenderTxns;

    struct MemberRate {
        address member;
        uint256 rate;
    }
    MemberRate[N_MEMBERS] public sortedRates;
    mapping(address => uint8) public memberRank;
    uint8 public noRates = N_MEMBERS;

    /**
     * @notice Returns contract balance
     * @dev The contract balance is publicly visible on-chain
     * @return balance Current contract balance
     */
    function treasuryReserve() public view returns (uint256) {
        return address(this).balance;
    }

    function proposeRate(uint256 newRate) external returns (uint8 newRank) {
        require(
            candidateInfo[msg.sender].electedMember,
            "Only members can propose"
        );
        require(newRate <= 5000, "Rate > 50%"); // Max 50% APR in basis points

        uint256 oldRate;
        uint8 oldRank = memberRank[msg.sender];
        uint8 rank;

        if (oldRank == 0 && noRates > 0) {
            // sortedRates[0].member != msg.sender
            noRates--;
            oldRate = 0;
            rank = noRates;
        } else {
            oldRate = sortedRates[oldRank].rate;
            rank = oldRank;
        }

        if (newRate == oldRate) {
            if (newRate == 0) {
                sortedRates[rank].member = msg.sender;
                memberRank[msg.sender] = rank;
                return rank;
            } else return oldRank;
        }

        if (newRate > oldRate) {
            // Push rates down
            while (
                rank < N_MEMBERS - 1 && newRate > sortedRates[rank + 1].rate
            ) {
                sortedRates[rank] = sortedRates[rank + 1];
                memberRank[sortedRates[rank].member] = rank;
                rank++;
            }
        } else {
            //(newRate < oldRate)
            // Push rates up
            while (rank > 0 && newRate < sortedRates[rank - 1].rate) {
                sortedRates[rank] = sortedRates[rank - 1];
                memberRank[sortedRates[rank].member] = rank;
                rank--;
            }
        }

        sortedRates[rank] = MemberRate({member: msg.sender, rate: newRate});
        memberRank[msg.sender] = rank;

        emit MemberRateChanged(msg.sender, oldRate, oldRank, newRate, rank);

        // Check if median changes
        if (currentRate != sortedRates[MEDIAN_MEMBER].rate) {
            currentRate = sortedRates[MEDIAN_MEMBER].rate;
            interestPeriods.push(
                InterestPeriod({rate: currentRate, startedAt: block.timestamp})
            );

            emit InterestRateUpdated(currentRate);
        }

        return rank; 
    }
    event MemberRateChanged(
        address indexed member,
        uint256 oldRate,
        uint8 oldRank,
        uint256 newRate,
        uint8 newRank
    );
    event InterestRateUpdated(uint256 newMedianRate);

    //   receive() external payable {
    function lend() external payable {
        Txn memory newTxn = Txn({
            amount: int256(msg.value),
            txnTime: block.timestamp
        });

        LenderTxns[msg.sender].push(newTxn);
        emit LoanReceived(msg.sender, int256(msg.value));
    }
    event LoanReceived(address indexed lender, int256 amount);

    function getBalance() external view returns (int256 _sum) {
        // Assuming rate = 0
        for (uint16 i; i < LenderTxns[msg.sender].length; i++) {
            _sum += LenderTxns[msg.sender][i].amount;
        }
        return _sum;
    }
}

contract Referendum is SharedStorage {
    uint256 public constant GOV_LENGTH = 10 weeks;
    uint256 public constant SUBMISSION_FEE = 1 ether / 1000;
    uint8 public constant MIN_DRAFTS = 10;
    uint32 public constant MIN_VOTERS = 1_000_000;
    uint32 public constant REF_VOTER_BATCH = 10; // voter batch size for the referendum
    uint256 public constant MAX_APPROVALS = 1000; // maximum registrar approval per member
    int256 public constant REQUIRED_SCORE = 10; // required approvals for each registrar
    uint256 public constant REQUIRED_REG = 2; // required number of registrations per voter

    struct ConstitutionDraft {
        string description; // Brief description or title
        string constitutionText; // Full text of the constitution
        string implementationCode; // Optional computer implementation
        string submitterIdentity; // Name/pseudonym/org/group
        bytes32 hashedOffChain; // Hash of above four fields
        string supportingMaterials; // IPFS hash for supporting files (PDF, video, etc.)
        uint256 submittedAt; // Time of submission
        uint256 voteCount; // Number of people voted for this draft
    }
    ConstitutionDraft[] public constitutionDrafts;

    mapping(bytes32 => address[REQUIRED_REG]) private voterRegistrars; // The registrars for each voter hash
    mapping(address => uint256) private referendumVotingTime;
    // 0:not registered, 1:registered once, 2: registered twice, time:voted at timestamp

    uint32 public referendumVoterCount;
    uint256 public ratifiedConstitutionId;

    mapping(address => mapping(address => int8)) private memberRegistrar; // member => registrar => vote (-1, 0, 1)
    mapping(address => int256) private registrarScore; // registrar => (approvals - disapprovals)
    mapping(address => uint256) private memberApprovalCount; // count of nonzero votes per member

    function submitDraft(ConstitutionDraft memory _draft) external payable {
        require(getCurrentPhase() == Phase.Governance, "Wrong phase");
        require(bytes(_draft.description).length > 0, "Description required");
        require(
            bytes(_draft.constitutionText).length > 0,
            "constitutionText required"
        );
        require(
            bytes(_draft.submitterIdentity).length > 0,
            "Proposer name required"
        );
        require(msg.value >= SUBMISSION_FEE, "Insufficient submission fee");

        bytes32 hashedOnChain = keccak256(
            abi.encodePacked(
                _draft.description,
                _draft.implementationCode,
                _draft.constitutionText,
                _draft.submitterIdentity
            )
        );

        require(hashedOnChain == _draft.hashedOffChain, "Incorrect Hash!");

        _draft.submittedAt = block.timestamp;
        _draft.voteCount = 0;

        constitutionDrafts.push(_draft);

        emit ConstitutionDraftSubmitted(constitutionDrafts.length - 1, _draft);
    }
    event ConstitutionDraftSubmitted(
        uint256 indexed draftId,
        ConstitutionDraft draft
    );

    function getConstitution(
        uint256 draftId
    ) external view returns (ConstitutionDraft memory) {
        require(
            draftId < constitutionDrafts.length,
            "Invalid constitution draft ID"
        );
        return constitutionDrafts[draftId];
    }

    function approveRegistrar(address registrar, int8 vote) external {
        require(candidateInfo[msg.sender].electedMember, "Not a member");
        require(vote >= -1 && vote <= 1, "Vote must be -1, 0, or 1");

        int8 oldVote = memberRegistrar[msg.sender][registrar];
        if (oldVote == 0 && vote != 0) {
            require(
                memberApprovalCount[msg.sender] < MAX_APPROVALS,
                "Max votes reached"
            );
            memberApprovalCount[msg.sender]++;
        } else if (oldVote != 0 && vote == 0) {
            memberApprovalCount[msg.sender]--;
        }

        memberRegistrar[msg.sender][registrar] = vote;
        registrarScore[registrar] += (vote - oldVote);
    }

    /**  
    * @notice Members: Two (randomly assigned) registrars required for double registration.  
    * @notice Registrar: Verify that (yearOfBirth <= 2006). 
    * @param voterAddresses[i]: Wallet addresses of the verified voters 
    * @param voterHashes[i]: Hash of FirstName+LastName+DoB(YYYY/MM/DD)+SSN+gender(male=0,female=1) 
    * @notice Registrar: Calculate hash offchain in frontend: 

    Example JavaScript Code: 
    const crypto = require('crypto'); 
    const firstName = "John";
    const lastName = "Doe";
    const yearOfBirth = 1995; // Before 2006 
    const monthOfBirth = 6;   // 06
    const dayOfBirth = 3;     // 03
    const gender = 1;         // Female
    const ssn = "123-45-6789";
    if (yearOfBirth > 2006) { 
        throw new Error("Must be born in or before 2006"); } 
    const dob = String(yearOfBirth) + String(monthOfBirth).padStart(2, '0') + String(dayOfBirth).padStart(2, '0')
    const input = firstName + lastName + ssn + dob + String(gender) ; 
    console.log(input); // "JohnDoe123-45-6789200606031" 
    const hash = crypto.createHash('sha256').update(input).digest('hex'); 
    console.log("Hash:", hash);
    */

    function registerVoterBatch(
        address[REF_VOTER_BATCH] calldata voterAddresses, // 10 voter addresses in any order
        bytes32[REF_VOTER_BATCH] calldata voterHashes // 10 voter hashes in any order
    ) external {
        require(
            registrarScore[msg.sender] >= REQUIRED_SCORE,
            "Not enough approval"
        );
        require(getCurrentPhase() == Phase.Governance, "Wrong phase");
        require(
            voterHashes.length == REF_VOTER_BATCH &&
                voterAddresses.length == REF_VOTER_BATCH,
            "Incorrect batch size"
        );

        // Check all hashes are new
        for (uint8 i = 0; i < REF_VOTER_BATCH; i++) {
            if (voterRegistrars[voterHashes[i]][0] == address(0)) {
                voterRegistrars[voterHashes[i]][0] = msg.sender;
            } else if (voterRegistrars[voterHashes[i]][1] == address(0)) {
                require(
                    voterRegistrars[voterHashes[i]][0] != msg.sender,
                    "Registrar must be different"
                );
                voterRegistrars[voterHashes[i]][1] = msg.sender;
            } else {
                revert("Hash already recorded");
            }
        }

        // Enable voting for all addresses
        for (uint8 i = 0; i < REF_VOTER_BATCH; i++) {
            require(voterAddresses[i] != address(0), "Invalid voter address");
            require(
                referendumVotingTime[voterAddresses[i]] < REQUIRED_REG,
                "Address already registered! REGISTRAR ERROR!"
            );
            referendumVotingTime[voterAddresses[i]]++;
        }

        referendumVoterCount += REF_VOTER_BATCH;

        emit VoterRegistered(voterAddresses, msg.sender, referendumVoterCount);
    }
    event VoterRegistered(
        address[REF_VOTER_BATCH] indexed voter,
        address registrar,
        uint256 referendumVoterCount
    );

    function getRegistrarsOfHash(
        bytes32 voterHash
    ) external view returns (address[REQUIRED_REG] memory) {
        return voterRegistrars[voterHash];
    }

    function getVoterStatus(
        address voterAddress
    ) external view returns (uint256) {
        return referendumVotingTime[voterAddress];
    }

    function startReferendum() external {
        require(
            electionEnd + GOV_LENGTH < block.timestamp,
            "Cannot start referendum yet"
        );
        require(ratifiedConstitutionId == 0, "Already ratified a constitution");
        require(constitutionDrafts.length > MIN_DRAFTS, "Not enough drafts");
        require(referendumVoterCount >= MIN_VOTERS, "Not enough voters");
        referendumEndTime = block.timestamp + 1 days;

        emit ReferendumStarted();
    }

    event ReferendumStarted();

    function voteInReferendum(uint256[] calldata _drafts) external {
        require(block.timestamp < referendumEndTime, "Not in Referendum time");
        require(
            _drafts.length <= constitutionDrafts.length,
            "Invalid draft list"
        );
        require(
            referendumVotingTime[msg.sender] == 2,
            "Voted or Not registered enough times"
        );

        bool[] memory votedForDrafts = new bool[](constitutionDrafts.length);

        for (uint256 i = 0; i < _drafts.length; i++) {
            uint256 _draftId = _drafts[i];
            require(_draftId < constitutionDrafts.length, "Invalid draft");
            require(!votedForDrafts[_draftId], "Repetitive draftId");
            votedForDrafts[_draftId] = true;
            constitutionDrafts[_draftId].voteCount++;
        }

        referendumVotingTime[msg.sender] = block.timestamp;
        emit ReferendumVoteCast(msg.sender);
    }
    event ReferendumVoteCast(address indexed voter);

    function getReferendumResults()
        external
        returns (uint256, ConstitutionDraft memory)
    {
        if (ratifiedConstitutionId > 0)
            return (
                ratifiedConstitutionId,
                constitutionDrafts[ratifiedConstitutionId]
            );

        require(
            referendumEndTime > 0 && referendumEndTime < block.timestamp,
            "Call once after Referendum"
        );

        uint256 _winningDraftId;
        uint256 _maxVotes = 0;

        for (uint256 i = 0; i < constitutionDrafts.length; i++) {
            if (constitutionDrafts[i].voteCount > _maxVotes) {
                _maxVotes = constitutionDrafts[i].voteCount;
                _winningDraftId = i;
            }
        }

        ratifiedConstitutionId = _winningDraftId;

        ConstitutionDraft memory _ratifiedConstitution = constitutionDrafts[
            _winningDraftId
        ];

        emit ConstitutionRatified(_winningDraftId, _ratifiedConstitution);

        return (_winningDraftId, _ratifiedConstitution);
    }
    event ConstitutionRatified(
        uint256 indexed winningProposalId,
        ConstitutionDraft ratifiedConstitution
    );
}

contract Elections is SharedStorage {}

contract SmartConstitution is Formation, Governance, Referendum, Finance {
    constructor(address neutralEntity, string memory interimConstitution) {
        neutral = neutralEntity;
        startTime = block.timestamp;
        electionEnd = startTime + REG_TIME + 1;
        Proposal storage _proposal = proposals.push();

        _proposal.proposer = msg.sender;
        _proposal.provisions = interimConstitution;
        _proposal.proposedAt = startTime;
        _proposal.executedAt = startTime;
        _proposal.withdrawnAt = 0;
        _proposal.yesVotes = N_MEMBERS;
    }
}