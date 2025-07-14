// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
 * Smart Constitution
 *
 * Designed and developed by:
 *   Dr. Daniel Armani (@dr-armani)
 *   LinkedIn: https://www.linkedin.com/in/dr-armani
 *   Website: https://blockcenter.org/ceo
 */

enum Phase {
    Registration, // Days 1-14: Candidate and voter registration
    Campaigning, // Days 15-28: Campaigning and debates
    Election, // 1 Day: Voting for the members of the transitional government
    Governance, // 10 weeks: Preparing constitution drafts
    Referendum, // 1 Day: Referendum day
    Ratification // New Constitution Ratified
}

struct Candidate {
    string fullName;
    string bio;
    string website;
    uint256 registeredAt;
    uint16 voteCount;
    uint8 memberID; // 0 if not elected, Member Index if one of the 50 members
    uint256 leaderAt; // 0 if never led, otherwise the week number they led
    uint16 activeProposal; // 0 if no active proposal, otherwise proposalId
    uint16 submittedDraft; // 0 if not submitted a draft, otherwise draftlId
}

struct Payment {
    uint256 amount;
    address recipient;
    string reason;
}

struct Proposal {
    address proposer;
    string provisions;
    uint256 executedAt;
    bool withdrawn;
    uint8 yesVotes;
    Payment[] payments;
}

contract SharedStorage {
    uint16 public constant RANDOM_VOTERS = 1200;
    uint256 public constant CAMPAIGN_DURATION = 2 weeks;
    uint8 public constant N_MEMBERS = 50;
    uint256 public RegistrationEnd;
    uint256 public electionEnd;
    uint256 public referendumEnd;
    uint16 public addedVoterCount;
    address[] public candidateList;
    mapping(address => Candidate) public candidateInfo;

    function getCurrentPhase() public returns (Phase) {
        if (block.timestamp < RegistrationEnd) return Phase.Registration;
        else if (
            candidateList.length < 2 * N_MEMBERS ||
            addedVoterCount < RANDOM_VOTERS
        ) {
            RegistrationEnd = 0;
            // Extend registration until there are at least 100 candidates and 1200 voters
            return Phase.Registration;
        } else if (RegistrationEnd == 0) {
            RegistrationEnd = block.timestamp;
            electionEnd = RegistrationEnd + CAMPAIGN_DURATION + 1 days;
            return Phase.Campaigning;
        } else if (block.timestamp < electionEnd - 1) return Phase.Campaigning;
        else if (block.timestamp < electionEnd) return Phase.Election;
        else if (referendumEnd == 0) return Phase.Governance;
        else if (block.timestamp < referendumEnd) return Phase.Referendum;
        else return Phase.Ratification;
        // else return Phase.Restart
    }
}

contract Formation is SharedStorage {
    uint8 public constant NEUTRAL_REGISTRARS = 3;
    uint256 public constant LEAD_PERIOD = 2 weeks;
    uint256 public constant REG_FEE = 1 ether / 1000;
    uint16 private constant VOTER_BATCH = 10;

    address[NEUTRAL_REGISTRARS] public agents;
    mapping(address => bool) public isAgent;

    mapping(bytes32 => mapping(address => bool)) private agentVoterHash; // Each Agent Verifies Each Voter Hash
    mapping(address => uint256) public voteTime; // 0:not registered, 1:registered, >1:voted at timestamp

    bool public membersElected = false;

    address public LeaderAddress;
    uint256 public LeaderId; // Member number of the Current Leader
    struct Demographic {
        uint16 birthYear;
        uint8 birthMonth;
        bool gender;
    }

    /**
     * @notice Neutral Agent: Verify ID and birthdate (1957 <= yearOfBirth <= 2006).
     * @param voterAddresses: Wallet addresses of the randomly selected voters
     * @param voterDemos: yearOfBirth(yyyy),monthOfBirth(mm),gender(male=0,female=1)
     */

    function addVoter(
        address[VOTER_BATCH] calldata voterAddresses, // 10 voters' addresses in a random order
        Demographic[VOTER_BATCH] calldata voterDemos // 10 voters' demographics in a random order
    ) external {
        require(isAgent[msg.sender], "Not an agent");
        require(
            getCurrentPhase() == Phase.Registration,
            "Registration period ended."
        );
        require(addedVoterCount < RANDOM_VOTERS, "Maximum number of voters.");
        require(
            voterDemos.length == VOTER_BATCH &&
                voterAddresses.length == VOTER_BATCH,
            "Incorrect batch size"
        );

        bytes32 _hashDemo;

        // Check all hashes are new
        for (uint8 i = 0; i < VOTER_BATCH; i++) {
            require(
                1957 <= voterDemos[i].birthYear &&
                    voterDemos[i].birthYear <= 2006,
                "Wrong Year"
            );
            require(
                1 <= voterDemos[i].birthMonth && voterDemos[i].birthMonth <= 12,
                "Invalid Month"
            );
            _hashDemo = keccak256(
                abi.encodePacked(
                    voterDemos[i].birthYear,
                    voterDemos[i].birthMonth,
                    voterDemos[i].gender
                )
            );
            require(
                !agentVoterHash[_hashDemo][msg.sender],
                "Already Verified this Voter"
            );
            agentVoterHash[_hashDemo][msg.sender] = true;
        }

        // Enable voting for all addresses
        for (uint8 i = 0; i < VOTER_BATCH; i++) {
            require(voterAddresses[i] != address(0), "Invalid address");
            require(
                voteTime[voterAddresses[i]] < NEUTRAL_REGISTRARS,
                "Already registered thrice. Registrar ERROR!"
            );
            voteTime[voterAddresses[i]]++;
        }

        addedVoterCount += VOTER_BATCH;

        emit VoterAdded(voterAddresses, addedVoterCount);
    }

    event VoterAdded(
        address[VOTER_BATCH] indexed voter,
        uint256 addedVoterCount
    );

    function getVoterStatus(
        address agentAddress,
        uint16 birthYear,
        uint8 birthMonth,
        bool gender
    ) external view returns (bool) {
        bytes32 _hashDemo = keccak256(
            abi.encodePacked(birthYear, birthMonth, gender)
        );
        return agentVoterHash[_hashDemo][agentAddress];
    }

    // function getVoteTime(address voterAddress) external view returns (uint256) {
    //     return voteTime[voterAddress];
    // }

    /**
     * @notice Register as a candidate with required information
     * @param _fullName Candidate's full name
     * @param _bio Brief biography of the candidate (education, experience, etc.)
     * @param _website Website URL for the candidate
     */

    function registerAsCandidate(
        string calldata _fullName,
        string calldata _bio,
        string calldata _website
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
        if (msg.value >= REG_FEE) {
            payable(msg.sender).transfer(msg.value - REG_FEE);
        } else {
            revert("Payment < registration fee");
        }
        require(
            getCurrentPhase() == Phase.Registration,
            "Registration period ended"
        );
        require(
            candidateInfo[msg.sender].registeredAt == 0,
            "Already registered"
        );
        Candidate storage candidate = candidateInfo[msg.sender];
        candidate.fullName = _fullName;
        candidate.bio = _bio;
        candidate.website = _website;
        candidate.registeredAt = block.timestamp;

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
            NEUTRAL_REGISTRARS < 2 * voteTime[msg.sender] && // At least 2 neutral registrars should validate the voter address
                voteTime[msg.sender] <= NEUTRAL_REGISTRARS, // Not voted yet.
            "Already voted (>1) or not registered (<2)"
        );

        bool[] memory votedFor = new bool[](candidateList.length);

        voteTime[msg.sender] = block.timestamp; // --> NEUTRAL_REGISTRARS < voteTime[msg.sender]
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

    function getElectionResults() external returns (address[] memory) {
        if (membersElected) {
            return candidateList;
        }
        require(block.timestamp > electionEnd, "Call after election");
        //unchecked {

        for (uint8 i = 1; i <= N_MEMBERS; i++) {
            for (uint256 j = candidateList.length - 1; i <= j; j--) {
                if (
                    candidateInfo[candidateList[j]].voteCount >
                    candidateInfo[candidateList[j - 1]].voteCount
                ) {
                    (candidateList[j], candidateList[j - 1]) = (
                        candidateList[j - 1],
                        candidateList[j]
                    );
                }
            }

            candidateInfo[candidateList[i - 1]].memberID = (i - 1);
        }

        membersElected = true;

        LeaderAddress = candidateList[0]; // = candidateList[candidateList.length - 1] ; Highest voted candidate
        LeaderId = 0;

        candidateInfo[LeaderAddress].leaderAt = block.timestamp;

        emit ElectionResults(candidateList, LeaderAddress);
        return candidateList;
    }

    event ElectionResults(address[] indexed candidateList, address firstLeader);

    function changeLeader() external {
        require(membersElected, "No leader yet");
        require(
            block.timestamp >=
                candidateInfo[LeaderAddress].leaderAt + LEAD_PERIOD,
            "Current leader's term not finished"
        );

        LeaderId++;
        LeaderAddress = candidateList[LeaderId];

        candidateInfo[LeaderAddress].leaderAt = block.timestamp;
        emit LeadershipChanged(LeaderAddress);
    }

    event LeadershipChanged(address indexed newLeader);
}

contract Governance is SharedStorage {
    uint8 public constant SUPER_MAJORITY = 30;
    Proposal[] public proposals;
    mapping(address => mapping(uint256 => bool)) public memberVoted;

    function proposeProposal(
        string calldata _provisions,
        Payment[] calldata _payments
    ) external returns (uint256) {
        require(bytes(_provisions).length > 0, "Provisions required");
        require(
            candidateInfo[msg.sender].memberID > 0,
            "Only members can propose proposals"
        );
        require(
            candidateInfo[msg.sender].activeProposal == 0,
            "Has an active proposal"
        );

        uint8 proposalId = uint8(proposals.length);
        candidateInfo[msg.sender].activeProposal = proposalId;

        proposals.push(); // Push empty proposal first
        Proposal storage newProposal = proposals[proposalId];

        newProposal.proposer = msg.sender;
        newProposal.provisions = _provisions;
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
            candidateInfo[msg.sender].memberID > 0,
            "Only members can vote"
        );
        require(proposalId < proposals.length, "Invalid proposal ID");

        Proposal storage proposal = proposals[proposalId];
        require(!proposal.withdrawn, "Proposal withdrawn");

        require(!memberVoted[msg.sender][proposalId], "Already voted");
        memberVoted[msg.sender][proposalId] = true;

        proposal.yesVotes++;

        emit ProposalVoted(proposalId, msg.sender);

        if (proposal.yesVotes >= SUPER_MAJORITY && proposal.executedAt == 0) {
            emit ProposalPassed(proposalId);
            proposal.executedAt = block.timestamp;
            candidateInfo[proposal.proposer].activeProposal = 0;
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
        require(proposal.executedAt == 0, "Already executed");
        require(!proposal.withdrawn, "Already withdrawn");

        proposal.withdrawn = true;
        candidateInfo[msg.sender].activeProposal = 0;
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

    // function getProposalInfo(
    //     uint256 proposalId
    // ) external view returns (Proposal memory) {
    //     require(proposalId < proposals.length, "Invalid proposal ID");
    //     return proposals[proposalId];
    // }
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
        uint256 rate;
    }
    mapping(address => Txn[]) public LenderTxns;

    struct MemberRate {
        address member;
        uint256 rate;
    }
    MemberRate[N_MEMBERS] public sortedRates;
    mapping(address => uint8) public memberRank;
    uint8 public noRates = N_MEMBERS;

    // function treasuryReserve() public view returns (uint256) {
    //     return address(this).balance;
    // }

    function proposeRate(uint256 newRate) external returns (uint8 newRank) {
        require(
            candidateInfo[msg.sender].memberID > 0,
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
            txnTime: block.timestamp,
            rate: currentRate
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
    uint256 public constant SUBMISSION_FEE = 0;
    uint8 public constant MIN_DRAFTS = 10;
    uint32 public constant MIN_VOTERS = 1_000_000;
    uint32 private constant VOTER_BATCH = 10; // voter batch size for the referendum
    uint256 public constant MAX_APPROVALS = 1000; // maximum registrar approval per member
    int256 public constant REQUIRED_SCORE = 10; // required approvals for each registrar
    uint256 public constant REQUIRED_REG = 2; // required number of registrations per voter

    struct ConstitutionDraft {
        string description; // Brief description or title
        string constitutionText; // Full text of the constitution
        string implementationCode; // Optional computer implementation
        string[] submitterIdentities; // Names/pseudonyms/organizations/groups
        bytes32 hashedOffChain; // Hash of above four fields
        string supportingMaterials; // IPFS hash for supporting files (PDF, video, etc.)
        uint256 submittedAt; // Time of submission
        uint256 voteCount; // Number of people voted for this draft
    }
    ConstitutionDraft[] public constitutionDrafts;

    mapping(bytes32 => address[REQUIRED_REG]) public voterRegistrars; // The registrars for each voter hash
    mapping(address => uint256) public referendumVoteTime;
    // 0:not registered, 1:registered once, 2: registered twice, time:voted at timestamp

    uint32 public referendumVoterCount;
    uint256 public ratifiedConstitutionId;

    mapping(address => mapping(address => int8)) private memberRegistrar; // member => registrar => vote (-1, 0, 1)
    mapping(address => int256) public registrarScore; // registrar => (approvals - disapprovals)
    mapping(address => uint256) private memberApprovalCount; // count of nonzero votes per member

    /**  
    @notice This function enables each Member to submit one constitution draft.
    @param draft The input should have the following fields:

    struct ConstitutionDraft {
        string description; // Brief description or title (required)
        string constitutionText; // Full text of the constitution (required)
        string implementationCode; // Computer implementation (optional)
        string[] submitterIdentities; // Names/pseudonyms/organizations/groups
        bytes32 hashedOffChain; // Hash of above four fields (Instructions below)
        string supportingMaterials; // IPFS hash for supporting files (PDF, video, etc.)
        uint256 submittedAt; // Time of submission (leave 0)
        uint256 voteCount; // Number of people voted for this draft (leave 0)
    }

    @dev Calculate the hash offchain in frontend.

    JavaScript Code: 

    const { keccak256, defaultAbiCoder } = require('ethers/lib/utils');

    const description = "The Modern Democratic Constitution of Liberal Republic";
    const constitutionText = "
    Article 1. The full text of the constitution draft is in this field. \n 
    Article 2. The longer texts consume more gas.";
    const implementationCode = ""; 

    const hashedOffChain = keccak256(defaultAbiCoder.encode(
        ["string", "string", "string"],
        [description, constitutionText, implementationCode]
    ));

    console.log("Hash:", hashedOffChain);
    */

    function submitDraft(ConstitutionDraft memory draft) external payable {
        require(candidateInfo[msg.sender].memberID > 0, "Not a member");
        require(
            candidateInfo[msg.sender].submittedDraft == 0,
            "Already submitted"
        );
        require(getCurrentPhase() == Phase.Governance, "Wrong phase");
        require(bytes(draft.description).length > 0, "Description required");
        require(
            bytes(draft.constitutionText).length > 0,
            "constitutionText required"
        );
        require(draft.submitterIdentities.length > 0, "At least one submitter");
        require(msg.value >= SUBMISSION_FEE, "Insufficient submission fee");

        bytes32 hashedOnChain = keccak256(
            abi.encodePacked(
                draft.description,
                draft.implementationCode,
                draft.constitutionText
            )
        );

        require(hashedOnChain == draft.hashedOffChain, "Incorrect Hash!");

        draft.submittedAt = block.timestamp;
        draft.voteCount = 0;

        candidateInfo[msg.sender].submittedDraft = uint16(
            constitutionDrafts.length
        );
        emit ConstitutionDraftSubmitted(constitutionDrafts.length, draft);
        constitutionDrafts.push(draft);
    }

    event ConstitutionDraftSubmitted(
        uint256 indexed draftId,
        ConstitutionDraft draft
    );

    // function getConstitution(
    //     uint256 draftId
    // ) external view returns (ConstitutionDraft memory) {
    //     require(
    //         draftId < constitutionDrafts.length,
    //         "Invalid constitution draft ID"
    //     );
    //     return constitutionDrafts[draftId];
    // }

    function approveRegistrar(address registrar, int8 vote) external {
        require(candidateInfo[msg.sender].memberID > 0, "Not a member");
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
    @notice Two different registrars required to double register each voter.  
    @notice Registrar: Verify ID and Age (yearOfBirth <= 2006). 
    @param voterAddresses[i]: Wallet addresses of the verified voters 
    @param voterHashes[i]: Hash of FirstName+LastName+DoB(YYYY/MM/DD)+SSN+gender(male=0,female=1) 
    @dev Calculate each hash offchain in frontend: 

    JavaScript Code: 

    const { keccak256, defaultAbiCoder } = require('ethers/lib/utils');

    const firstName = "John";
    const lastName = "Doe";
    const ssn = "123-45-6789"; // Include dashes
    const yearOfBirth = 1995;  // Before 2006 
    const monthOfBirth = 6;    // 06
    const dayOfBirth = 3;      // 03
    const gender = true;       // Female

    if (yearOfBirth > 2006) { 
        throw new Error("Must be born in or before 2006");
    }

    const hash = keccak256(defaultAbiCoder.encode(
        ["string", "string", "string", "uint16", "uint8", "uint8", "uint8", "bool"],
        [firstName, lastName, ssn, yearOfBirth, monthOfBirth, dayOfBirth, gender]
    ));

    console.log("Hash:", hash);
    */

    function registerVoterBatch(
        address[VOTER_BATCH] calldata voterAddresses, // 10 voter addresses in any order
        bytes32[VOTER_BATCH] calldata voterHashes // 10 voter hashes in any order
    ) external {
        require(
            registrarScore[msg.sender] >= REQUIRED_SCORE,
            "Not enough approval"
        );
        require(getCurrentPhase() == Phase.Governance, "Wrong phase");
        require(
            voterHashes.length == VOTER_BATCH &&
                voterAddresses.length == VOTER_BATCH,
            "Incorrect batch size"
        );

        // Check all hashes are new
        for (uint8 i = 0; i < VOTER_BATCH; i++) {
            if (voterRegistrars[voterHashes[i]][0] == address(0)) {
                voterRegistrars[voterHashes[i]][0] = msg.sender;
            } else if (voterRegistrars[voterHashes[i]][1] == address(0)) {
                require(
                    voterRegistrars[voterHashes[i]][0] != msg.sender,
                    "Same Registrar"
                );
                voterRegistrars[voterHashes[i]][1] = msg.sender;
            } else {
                revert("Hash already recorded");
            }
        }

        // Enable voting for all addresses
        for (uint8 i = 0; i < VOTER_BATCH; i++) {
            require(voterAddresses[i] != address(0), "Invalid voter address");
            require(
                referendumVoteTime[voterAddresses[i]] < REQUIRED_REG,
                "Address already registered! REGISTRAR ERROR!"
            );
            referendumVoteTime[voterAddresses[i]]++;
        }

        referendumVoterCount += VOTER_BATCH;

        emit VoterRegistered(voterAddresses, msg.sender, referendumVoterCount);
    }

    event VoterRegistered(
        address[VOTER_BATCH] indexed voter,
        address registrar,
        uint256 referendumVoterCount
    );

    // function getRegistrarsOfHash(
    //     bytes32 voterHash
    // ) external view returns (address[REQUIRED_REG] memory) {
    //     return voterRegistrars[voterHash];
    // }

    // function getVoterStatus(
    //     address voterAddress
    // ) external view returns (uint256) {
    //     return referendumVoteTime[voterAddress];
    // }

    function startReferendum() external {
        require(
            electionEnd + GOV_LENGTH < block.timestamp,
            "Cannot start referendum yet"
        );
        require(ratifiedConstitutionId == 0, "Already ratified");
        require(constitutionDrafts.length > MIN_DRAFTS, "Not enough drafts");
        require(referendumVoterCount >= MIN_VOTERS, "Not enough voters");
        referendumEnd = block.timestamp + 1 days;

        emit ReferendumStarted();
    }

    event ReferendumStarted();

    function voteInReferendum(uint256[] calldata _drafts) external {
        require(block.timestamp < referendumEnd, "Not Referendum time");
        require(
            _drafts.length <= constitutionDrafts.length,
            "Invalid draft list"
        );
        require(
            referendumVoteTime[msg.sender] == REQUIRED_REG,
            "Voted or Not registered"
        );

        bool[] memory votedForDrafts = new bool[](constitutionDrafts.length);

        for (uint256 i = 0; i < _drafts.length; i++) {
            uint256 _draftId = _drafts[i];
            require(_draftId < constitutionDrafts.length, "Invalid draft");
            require(!votedForDrafts[_draftId], "Repetitive draftId");
            votedForDrafts[_draftId] = true;
            constitutionDrafts[_draftId].voteCount++;
        }

        referendumVoteTime[msg.sender] = block.timestamp;
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
            referendumEnd > 0 && referendumEnd < block.timestamp,
            "Call after Referendum"
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

// contract Elections is SharedStorage {}

/// @author Dr. Daniel Armani
contract SmartConstitution is Formation, Governance, Referendum, Finance {
    uint256 public immutable startTime;

    constructor(
        address[NEUTRAL_REGISTRARS] memory _neutralAgents,
        string memory _interimConstitution
    ) {
        agents = _neutralAgents;

        startTime = block.timestamp;
        RegistrationEnd = startTime + 4 weeks;
        electionEnd = RegistrationEnd + CAMPAIGN_DURATION + 1 days;

        // proposals[0] is this Interim Constitution
        Proposal storage _proposal = proposals.push();
        _proposal.proposer = msg.sender;
        _proposal.provisions = _interimConstitution;
        _proposal.executedAt = startTime;
        _proposal.withdrawn = false;
        _proposal.yesVotes = N_MEMBERS;
    }
}
