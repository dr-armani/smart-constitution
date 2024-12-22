// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum Phase {
    Registration, // Days 1-14: Candidate and voter registration
    Election, // 1 Day: Voting for the transitional government
    Governance, // 10 weeks: Collecting constitution proposals
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

struct Bill {
    address proposer;
    string provisions;
    uint256 proposedAt;
    uint256 executedAt;
    uint256 withdrawnAt;
    uint8 yesVotes;
    Payment[] payments;
    //mapping(address => uint256) memberVotedAt;
}

contract SmartConstitution {
    uint32 public constant RANDOM_VOTERS = 1000; // between 1000 and 2000 random voters
    uint256 public constant REG_TIME = 2 weeks;
    uint8 public constant N_MEMBERS = 50;
    uint256 public immutable startTime;
    uint256 public electionEnd;
    address public randomizer; // Address of the international oversight agent to find random voters.
    uint32 addedVoterCount;
    address[] public candidateList;
    Bill[] public bills; // bills[0] is the transitional constitution.
    uint256 public referendumEndTime;

    mapping(address => Candidate) public candidateInfo;

    constructor(address _randomizer, string memory _provisions) {
        randomizer = _randomizer;
        startTime = block.timestamp;
        electionEnd = startTime + REG_TIME + 1;
        Bill storage _bill = bills.push();

        _bill.proposer = msg.sender;
        _bill.provisions = _provisions;
        _bill.proposedAt = startTime;
        _bill.executedAt = startTime;
        _bill.withdrawnAt = 0;
        _bill.yesVotes = N_MEMBERS;
    }

    function getCurrentPhase() public returns (Phase) {
        if (block.timestamp < electionEnd - 1 days) return Phase.Registration;
        else if (block.timestamp < electionEnd)
            if (
                candidateList.length < 2 * N_MEMBERS ||
                addedVoterCount < RANDOM_VOTERS
            ) {
                // Postpone election for two weeks if fewer than 100 candidates or fewer than 1000 voters
                electionEnd = electionEnd + REG_TIME;
                return Phase.Registration;
            } else return Phase.Election;
        else if (referendumEndTime == 0) return Phase.Governance;
        // membersElected
        else if (block.timestamp < referendumEndTime) return Phase.Referendum;
        else return Phase.Ratification;
        // else return Phase.Restart
    }
}

abstract contract InitialVoting is SmartConstitution {
    uint256 public constant LEAD_PERIOD = 1 weeks;
    uint256 public constant REG_FEE = 1 ether / 1000;
    uint32 public constant VOTER_BATCH = 10;

    mapping(bytes32 => bool) private isVoterHash; // Random voter hash
    mapping(address => uint256) private voteTime; // 0:not registered, 1:registered, >1:voted at timestamp

    address[N_MEMBERS] private electedMembers;
    bool public membersElected = false;
    
    address public currentLeaderAddress;
    uint256 public currentLeaderNumber; // 1 to 50 representing position from highest voted


    // offchain/frontend: voterHashes[i] = hash(FirstName+LastName+DoB(YYYY/MM/DD)+SSN)
    // JavaScript:
    // const crypto = require('crypto');
    // const input = firstName + lastName + dob + ssn;
    // const hash = crypto.createHash('sha256').update(input).digest('hex');
    function addVoter(
        bytes32[VOTER_BATCH] calldata voterHashes, // 10 voter hashes in any order
        address[VOTER_BATCH] calldata voterAddresses // 10 voter addresses in any order
    ) public {
        require(msg.sender == randomizer, "Not authorized randomizer");
        require(
            getCurrentPhase() == Phase.Registration,
            "Voter adding period has ended."
        );
        require(
            addedVoterCount <= 2 * RANDOM_VOTERS,
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
            bytes(_website).length > 0 && bytes(_website).length <= 2000,
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
    function voteCandidates(uint256[] calldata _candidatesIds) public {
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

    function getElectionResults() public returns (address[N_MEMBERS] memory) {
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
        
    function changeLeader() public {
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

abstract contract Governance is SmartConstitution{
    uint8 public constant SUPER_MAJORITY = 30;

    mapping(address => uint256) public activeBillByMember; // 0 if no active bill, otherwise billId
    mapping(address => mapping(uint256 => uint256)) public memberVotedAt;

    function proposeBill(
        string calldata _provisions,
        Payment[] calldata _payments
    ) external returns (uint256) {
        require(
            candidateInfo[msg.sender].electedMember,
            "Only members can propose bills"
        );
        require(bytes(_provisions).length > 0, "Provisions required");
        require(
            activeBillByMember[msg.sender] == 0,
            "Member already has an active bill"
        );

        uint256 billId = bills.length;
        activeBillByMember[msg.sender] = billId;

        bills.push(); // Push empty bill first
        Bill storage newBill = bills[billId];

        newBill.proposer = msg.sender;
        newBill.provisions = _provisions;
        newBill.proposedAt = block.timestamp;
        // Copy payments array
        for (uint256 i = 0; i < _payments.length; i++) {
            newBill.payments.push(_payments[i]);
        }

        emit BillProposed(bills.length, msg.sender, _provisions);
        return bills.length;
    }
    event BillProposed(
        uint256 indexed billId,
        address indexed proposer,
        string provisions
    );

    function voteForBill(uint256 billId) external returns (uint8) {
        require(
            candidateInfo[msg.sender].electedMember,
            "Only members can vote"
        );
        require(billId < bills.length, "Invalid bill ID");

        Bill storage bill = bills[billId];
        require(bill.withdrawnAt == 0, "Bill withdrawn");
        //require(bill.memberVotedAt[msg.sender]==0, "Already voted");
        //bill.memberVotedAt[msg.sender] = block.timestamp;

        require(memberVotedAt[msg.sender][billId] == 0, "Already voted");
        memberVotedAt[msg.sender][billId] = block.timestamp;

        bill.yesVotes++;

        emit BillVoted(billId, msg.sender);

        if (bill.yesVotes >= SUPER_MAJORITY && bill.executedAt == 0) {
            emit BillPassed(billId);
            bill.executedAt = block.timestamp;
            activeBillByMember[bill.proposer] = 0;
            _executeBill(billId);
        }

        return bill.yesVotes;
    }
    event BillVoted(uint256 indexed billId, address indexed voter);
    event BillPassed(uint256 indexed billId);

    function withdrawBill(uint256 billId) external {
        require(billId < bills.length, "Invalid bill ID");
        Bill storage bill = bills[billId];
        require(bill.proposer == msg.sender, "Only the proposer can withdraw");
        require(bill.executedAt == 0, "Bill already executed");
        require(bill.withdrawnAt == 0, "Bill already withdrawn");

        bill.withdrawnAt = block.timestamp;
        activeBillByMember[msg.sender] = 0;

        emit BillWithdrawn(billId);
    }
    event BillWithdrawn(uint256 indexed billId);

    function _executeBill(uint256 billId) internal {
        Bill storage bill = bills[billId];
        for (uint256 i; i < bill.payments.length; i++) {
            Payment memory payment = bill.payments[i];
            payable(payment.recipient).transfer(payment.amount);
        }
    }

    function getBillInfo(uint256 billId) external view returns (Bill memory) {
        require(billId < bills.length, "Invalid bill ID");
        return bills[billId];
    }

    function getVotingTimeBill(
        uint256 billId,
        address memberAddress
    ) external view returns (uint256) {
        require(billId < bills.length, "Invalid bill ID");
        require(candidateInfo[memberAddress].electedMember, "Not a Member");
        // return bills[billId].memberVotedAt[memberAddress];

        return memberVotedAt[memberAddress][billId];
    }

    function getMemberActiveBill(
        address memberAddress
    ) external view returns (uint256) {
        require(candidateInfo[memberAddress].electedMember, "Not a Member");
        return activeBillByMember[memberAddress];
    }
}

abstract contract Referendum is SmartConstitution{
    uint256 public constant GOV_LENGTH = 10 weeks;
    uint256 public constant SUBMISSION_FEE = 1 ether / 1000;
    uint8 public constant MIN_PROPOSALS = 10;
    uint32 public constant MIN_VOTERS = 1_000_000;

    struct ConstitutionProposal {
        string description; // Brief description or title
        string constitutionText; // Full text of the constitution
        string implementationCode; // Optional computer implementation
        string proposerIdentity; // Name/pseudonym/org/group
        bytes32 hashedOffChain; // Hash of above four fields
        string supportingMaterials; // IPFS hash for supporting files (PDF, video, etc.)
        uint256 submittedAt; // Time of submission
        uint256 voteCount; // Number of people voted for this proposal
    }

    uint256 public proposalCount;
    ConstitutionProposal[] public constitutionProposals;

    mapping(bytes32 => address[2]) private registrarsVoter; // The registrars for each voter hash
    mapping(address => uint256) private referendumVotingTime;
    // 0:not registered, 1:registered once, 2: registered twice, >2:voted at timestamp

    uint32 public referendumVoterCount;

    uint256 public ratifiedConstitutionId;

    function proposeConstitution(
        ConstitutionProposal memory _proposal
    ) public payable {
        require(getCurrentPhase() == Phase.Governance, "Wrong phase");
        require(
            bytes(_proposal.description).length > 0,
            "Description required"
        );
        require(
            bytes(_proposal.constitutionText).length > 0,
            "constitutionText required"
        );
        require(
            bytes(_proposal.proposerIdentity).length > 0,
            "Proposer name required"
        );
        require(msg.value >= SUBMISSION_FEE, "Insufficient submission fee");

        bytes32 hashedOnChain = keccak256(
            abi.encodePacked(
                _proposal.description,
                _proposal.implementationCode,
                _proposal.constitutionText,
                _proposal.proposerIdentity
            )
        );

        require(hashedOnChain == _proposal.hashedOffChain, "Incorrect Hash!");

        _proposal.submittedAt = block.timestamp;
        _proposal.voteCount = 0;

        constitutionProposals.push(_proposal);

        emit ConstitutionProposalSubmitted(
            constitutionProposals.length - 1,
            _proposal
        );
    }

    event ConstitutionProposalSubmitted(
        uint256 indexed proposalId,
        ConstitutionProposal proposal
    );

    function getConstitution(
        uint256 proposalId
    ) public view returns (ConstitutionProposal memory) {
        require(
            proposalId < constitutionProposals.length,
            "Invalid constitution proposal ID"
        );
        return constitutionProposals[proposalId];
    }

    // members can hire and fire registrars
    uint32 public constant REF_VOTER_BATCH = 10;
    uint256 public constant MAX_APPROVALS = 1000;
    int256 public constant REQUIRED_SCORE = 10;

    mapping(address => mapping(address => int8)) public memberRegistrar; // member => registrar => vote (-1, 0, 1)
    mapping(address => int256) public registrarScore; // registrar => (approvals - disapprovals)
    mapping(address => uint256) public memberApprovalCount; // count of +1 votes per member

    function approveRegistrar(address registrar, int8 vote) public {
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

    // Multiple Registrars required for registration
    // Registrars are randomly assigned to voters.
    // offchain/frontend: voterHashes[i] = hash(FirstName+LastName+DoB(YYYY/MM/DD)+SSN)
    function registerVoterBatch(
        bytes32[REF_VOTER_BATCH] calldata voterHashes, // 10 voter hashes in any order
        address[REF_VOTER_BATCH] calldata voterAddresses // 10 voter addresses in any order
    ) public {
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
            if (registrarsVoter[voterHashes[i]][0] == address(0)) {
                registrarsVoter[voterHashes[i]][0] = msg.sender;
            } else if (registrarsVoter[voterHashes[i]][1] == address(0)) {
                registrarsVoter[voterHashes[i]][1] = msg.sender;
            } else {
                revert("Voter hash already registered.");
            }
        }

        // Enable voting for all addresses
        for (uint8 i = 0; i < REF_VOTER_BATCH; i++) {
            require(voterAddresses[i] != address(0), "Invalid voter address");
            require(
                referendumVotingTime[voterAddresses[i]] < 2,
                "Addresss already registered. Registrar ERROR!"
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
    ) external view returns (address[2] memory) {
        return registrarsVoter[voterHash];
    }

    function getVoterStatus(
        address voterAddress
    ) external view returns (uint256) {
        return referendumVotingTime[voterAddress];
    }

    function startReferendum() public {
        require(
            electionEnd + GOV_LENGTH < block.timestamp,
            "Cannot start referendum yet"
        );
        require(ratifiedConstitutionId == 0, "Already ratified a constitution");
        require(
            constitutionProposals.length > MIN_PROPOSALS,
            "Not enough proposals"
        );
        require(referendumVoterCount >= MIN_VOTERS, "Not enough voters");
        referendumEndTime = block.timestamp + 1 days;

        emit ReferendumStarted();
    }

    event ReferendumStarted();

    function voteInReferendum(uint256[] calldata _proposals) external {
        require(block.timestamp < referendumEndTime, "Not in Referendum time");
        require(
            _proposals.length <= constitutionProposals.length,
            "Invalid proposal list"
        );
        require(
            referendumVotingTime[msg.sender] == 2,
            "Voted or Not registered enough times"
        );

        bool[] memory votedForProposal = new bool[](
            constitutionProposals.length
        );

        for (uint256 i = 0; i < _proposals.length; i++) {
            uint256 _proposalId = _proposals[i];
            require(
                _proposalId < constitutionProposals.length,
                "Invalid proposal"
            );
            require(!votedForProposal[_proposalId], "Repetitive proposalId");
            votedForProposal[_proposalId] = true;
            constitutionProposals[_proposalId].voteCount++;
        }

        referendumVotingTime[msg.sender] = block.timestamp;
        emit ReferendumVoteCast(msg.sender);
    }

    event ReferendumVoteCast(address indexed voter);

    function getReferendumResults()
        external
        returns (uint256, ConstitutionProposal memory)
    {
        if (ratifiedConstitutionId > 0)
            return (
                ratifiedConstitutionId,
                getConstitution(ratifiedConstitutionId)
            );

        require(
            referendumEndTime > 0 && referendumEndTime < block.timestamp,
            "Call once after Referendum"
        );

        uint256 _winningProposalId;
        uint256 _maxVotes = 0;

        for (uint256 i = 0; i < constitutionProposals.length; i++) {
            if (constitutionProposals[i].voteCount > _maxVotes) {
                _maxVotes = constitutionProposals[i].voteCount;
                _winningProposalId = i;
            }
        }

        ratifiedConstitutionId = _winningProposalId;

        ConstitutionProposal
            memory _ratifiedConstitution = constitutionProposals[
                _winningProposalId
            ];

        emit ConstitutionRatified(_winningProposalId, _ratifiedConstitution);

        return (_winningProposalId, _ratifiedConstitution);
    }

    event ConstitutionRatified(
        uint256 indexed winningProposalId,
        ConstitutionProposal ratifiedConstitution
    );
}

abstract contract Financial is SmartConstitution{
    uint8 constant MEDIAN_MEMBER = uint8(N_MEMBERS / 2);

    uint256 public currentRate;
    struct InterestPeriod {
        uint256 rate; // Interest rate in basis points
        uint256 startedAt; // When this rate becomes effective
    }
    InterestPeriod[] public interestPeriods;

    struct Txn {
        int256 amount;
        uint256 timestamp;
    }
    mapping(address => Txn[]) public LenderTxns;

    struct MemberRate {
        address member;
        uint256 rate;
    }
    MemberRate[N_MEMBERS] public sortedRates;
    mapping(address => uint8) public memberRank;
    uint8 public numberOfRates = 0;

    /**
     * @notice Returns contract balance
     * @dev The contract balance is publicly visible on-chain
     * @return balance Current contract balance
     */
    function treasuryReserve() public view returns (uint256) {
        return address(this).balance;
    }

    function proposeRate(uint256 newRate) external {
        require(
            candidateInfo[msg.sender].electedMember,
            "Only members can propose"
        );
        require(newRate <= 5000, "Rate cannot exceed 50%"); // Max 50% APR in basis points

        uint256 oldRate;
        uint8 oldRank = memberRank[msg.sender];

        if (oldRank == 0 && sortedRates[oldRank].member != msg.sender) {
            numberOfRates++;
            oldRate = 0;
        } else {
            oldRate = sortedRates[oldRank].rate;
        }

        uint8 newRank = oldRank;

        if (newRate == oldRate) {
            return;
        } else if (newRate > oldRate) {
            // Move rates down
            while (
                newRank < N_MEMBERS - 1 &&
                newRate > sortedRates[newRank + 1].rate
            ) {
                sortedRates[newRank] = sortedRates[newRank + 1];
                memberRank[sortedRates[newRank].member] = newRank; // null if no member??
                newRank++;
            }
        } else {
            //(newRate < oldRate)
            // Move rates up
            while (newRank > 0 && newRate < sortedRates[newRank - 1].rate) {
                sortedRates[newRank] = sortedRates[newRank - 1];
                memberRank[sortedRates[newRank].member] = newRank;
                newRank--;
            }
        }

        sortedRates[newRank] = MemberRate({member: msg.sender, rate: newRate});
        memberRank[msg.sender] = newRank;

        emit MemberRateChanged(msg.sender, oldRate, oldRank, newRate, newRank);

        // Check if median changes
        if (currentRate != sortedRates[MEDIAN_MEMBER].rate) {
            currentRate = sortedRates[MEDIAN_MEMBER].rate;
            interestPeriods.push(
                InterestPeriod({rate: currentRate, startedAt: block.timestamp})
            );

            emit InterestRateUpdated(currentRate);
        }
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
            timestamp: block.timestamp
        });

        LenderTxns[msg.sender].push(newTxn);
        emit LoanReceived(msg.sender, int256(msg.value));
    }
    event LoanReceived(address indexed lender, int256 amount);

    function getBalance() external view returns (int256 _sum) {
        for (uint16 i; i < LenderTxns[msg.sender].length; i++) {
            _sum += LenderTxns[msg.sender][i].amount;
        }
        return _sum;
    }
}
