// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SmartConstitution { 
    uint256 public constant RANDOM_VOTERS = 1000; // between 1000 and 2000 random voters initially
    uint256 public constant MIN_VOTES = 500; 

    uint256 public constant REGISTRATION_PERIOD = 2 weeks; 
    uint256 public constant REGISTRATION_FEE = 1 ether / 1000; 

    uint8 public constant TOTAL_MEMBERS = 50;  
    uint8 constant MEDIAN_MEMBER = uint8(TOTAL_MEMBERS / 2); 
    uint256 public constant SUPER_MAJORITY = 30; 
    uint256 public constant LEADER_PERIOD = 1 weeks; 

    uint256 public constant SUBMISSION_FEE = 1 ether / 1000; 
    uint256 public constant MINIMUM_PROPOSALS = 10; 
    
    uint256 public constant VOTER_BATCH = 10;
    uint256 public constant MINIMUM_VOTERS = 1_000_000; 

    uint256 public constant GOVERNANCE_LENGTH = 10 weeks; 

    address public randomizer; // Address of the international oversight agent to find random voters.

    uint256 public immutable startTime;
    uint256 public electionEnd;

    mapping(address => uint256) private electionVotingTime; // 0:not voter, 1:can vote, >1:voted at timestamp
    uint16 electionVoterCount;

    struct Candidate {
        string fullname;
        string bio;
        string website;
        uint256 registrationTime;
        uint256 totalVotes;
        bool electedMember; // true if they became one of the 50 members
        uint256 leadershipTime; // 0 if never led, otherwise the week number they led
    } 

    mapping(address => Candidate) public candidates;
    address[] public candidateList;
    address[TOTAL_MEMBERS] private members;
    bool public membersElected = false;

    address public currentLeaderAddress;
    uint256 public currentLeaderNumber; // 1 to 50 representing position from highest voted

    struct Payment{
        uint256 amount;
        address recipient;
        string reason;
    }
    struct Bill {
        address proposer; 
        string provisions; 
        uint256 proposalTime; 
        uint256 executionTime; 
        uint256 withdrawalTime; 
        uint8 yesVotes; 
        Payment[] payments; 
        mapping(address => uint256) memberVotingTime; 
    }
    Bill[] public bills; // bills[0] is the transitional constitution. 
    mapping(address => uint256) public activeBillByMember; // 0 if no active bill, otherwise billId 

    struct ConstitutionProposal {
        string description; // Brief description or title
        string draft; // Full text of the constitution
        string code; // Optional computer implementation
        string proposer; // Name/pseudonym/org/group
        bytes32 hashedOffChain; // Hash of above four fields
        string supportingMaterials; // IPFS hash for supporting files (PDF, video, etc.)
        uint256 submissionTime; // Time of submission
        uint256 totalVotes; // Number of people voted for this proposal
    }

    uint256 public proposalCount;
    ConstitutionProposal[] public proposals;
    
    uint256 public referendumEndTime;
    uint256 public ratifiedConstitutionId;

    mapping(bytes23 => address) private registrarVoterHashes; // The registrar for each voter hash  
    mapping(address => uint256) public referendumVotingTime; // 0:not voter, 1:can vote, >1:voted at timestamp
    uint16 public referendumVoterCount;

    uint256 public currentRate;
    struct InterestPeriod {
        uint256 rate; // Interest rate in basis points
        uint256 startTime; // When this rate becomes effective
    }
    InterestPeriod[] public interestPeriods;

    struct Loan {
        uint256 amount;
        uint256 timestamp;
    }
    mapping(address => Loan[]) public loansByLender;

    struct MemberRate {
        address member;
        uint256 rate;
    }
    MemberRate[TOTAL_MEMBERS] public sortedRates; 
    mapping(address => uint8) public memberRank;
    uint8 public numberOfRates = 0;

    constructor(address _randomizer, string memory _provisions) { 
        randomizer = _randomizer;
        startTime = block.timestamp;
        electionEnd = startTime + REGISTRATION_PERIOD + 1; 
        
        bills.push(Bill({
            proposer: msg.sender,
            provisions: _provisions,
            proposalTime: startTime,
            executionTime: startTime,
            withdrawalTime: 0, 
            yesVotes: TOTAL_MEMBERS 
        }));
    }

    event VoterAdded(address indexed voter, uint256 totalVoters);
    event CandidateRegistered(
        address indexed candidate,
        string fullname,
        string bio,
        string website
    );

    event ElectionResults(address[TOTAL_MEMBERS] indexed members, address firstLeader);
    event LeadershipChanged(address indexed newLeader);
    event NewProposal(
        uint256 indexed proposalId,
        string description,
        string draft,
        string code,
        string proposer,
        string supportingMaterials
    );
    event VoterRegistered(address[VOTER_BATCH] indexed voter, address registrar, uint256 totalVoters); 
    event ReferendumStarted();
    event VoteCastReferendum(address indexed voter, uint256[] proposals);
    event ConstitutionRatified(
        uint256 indexed winningProposalId,
        uint256 maxVotes,
        string description,
        string draft,
        string code,
        string proposer,
        string supportingMaterials
    );
    event MemberRateChanged(
        address indexed member,
        uint256 oldRate,
        uint8 oldRank,
        uint256 newRate, 
        uint8 newRank
    );
    event InterestRateUpdated(uint256 currentRate); 
    event LoanReceived(address indexed lender, uint256 amount);

    enum Phase {
        Registration, // Days 1-14: Candidate and voter registration
        Election, // 1 Day: Voting for the transitional government
        Governance, // 10 weeks: Collecting Proposals
        Referendum, // 1 Day: Referendum day
        Ratification // New Constitution Ratified
    }

    function getCurrentPhase() public returns (Phase) {
        if (block.timestamp < electionEnd - 1 days) return Phase.Registration;
        else if (block.timestamp < electionEnd)
            if (candidateList.length < 2*TOTAL_MEMBERS || electionVoterCount < RANDOM_VOTERS) {
                // Postpone election for two weeks if fewer than 100 candidates or fewer than 1000 voters
                electionEnd = electionEnd + REGISTRATION_PERIOD; 
                return Phase.Registration; 
            } else return Phase.Election;
        else if (referendumEndTime == 0) return Phase.Governance;   // membersElected
        else if (block.timestamp < referendumEndTime) return Phase.Referendum;
        else return Phase.Ratification; 
        // else return Phase.Restart
    }

    function addVoter(address voter) public {
        require(msg.sender == randomizer, "Not authorized randomizer");
        require( 
            getCurrentPhase() == Phase.Registration,
            "Voter registration period has ended."
        );
        require(
            electionVoterCount <= 2 * RANDOM_VOTERS,
            "Maximum number of voters reached."
        ); 
        require(voter != address(0), "Invalid voter address");
        require(
            electionVotingTime[voter] == 0,
            "Address is already registered as a voter"
        );

        electionVotingTime[voter] = 1; // Register a random voter
        electionVoterCount++;

        emit VoterAdded(voter, electionVoterCount); 
    }

    /** 
     * @notice Register as a candidate with required information
     * @param fullname Candidate's full name
     * @param bio Brief biography of the candidate
     * @param website Additional relevant information (education, experience, etc.)
     */

    function registerAsCandidate(
        string memory fullname, 
        string memory bio,
        string memory website
    ) external payable { 
        require(bytes(fullname).length > 0 && bytes(fullname).length <= 100, "Invalid name");
        require(bytes(bio).length > 0 && bytes(bio).length <= 1000, "Invalid bio");
        require(bytes(website).length > 0 && bytes(website).length <= 2000, "Invalid website");
        require(msg.sender != address(0), "Invalid sender");
        require(msg.value >= REGISTRATION_FEE, "Insufficient registration fee");
        require(
            getCurrentPhase() == Phase.Registration,
            "Candidate registration period has ended."
        );
        require(
            candidates[msg.sender].registrationTime == 0,
            "Already registered" 
        );
        candidates[msg.sender] = Candidate({
            fullname: fullname,
            bio: bio,
            website: website,
            registrationTime: block.timestamp,
            totalVotes: 0,
            electedMember: false,
            leadershipTime: 0
        });

        candidateList.push(msg.sender); 
        emit CandidateRegistered(msg.sender, fullname, bio, website); 
    }

    function getCandidateInfo(uint256 candidateID) external view returns(Candidate memory)
    {
        require(candidateID < candidateList.length, "Invalid Candidate ID");
        return candidates[candidateList[candidateID]];
    }

    //mapping(address => uint256[]) private voter2Candidates; 
    function voteCandidatesAsMembers(uint256[] calldata _candidatesIndices) public {
        require(getCurrentPhase() == Phase.Election, "Not in Election phase");
        require(
            _candidatesIndices.length <= candidateList.length, 
            "Invalid vote count" 
        );
        require(
            electionVotingTime[msg.sender] == 1,
            "Already voted (>1) or not registered (0)"
        );

        bool[] memory votedFor = new bool[](candidateList.length);

        electionVotingTime[msg.sender] = block.timestamp;
        emit VoteCast(msg.sender); 

        for (uint i = 0; i < _candidatesIndices.length; i++) {
            uint256 _candidateId = _candidatesIndices[i];
            require(_candidateId < candidateList.length, "Wrong candidate index");

            if (!votedFor[_candidateId]) {
                votedFor[_candidateId] = true; 
                candidates[candidateList[_candidateId]].totalVotes++;
                // voter2Candidates[msg.sender].push(_candidateId); 
            }
        }
    }
    event VoteCast(address indexed voter); 
 
    function getElectionResults() public returns (address[TOTAL_MEMBERS] memory) {
        require(block.timestamp > electionEnd,"Call after election");

        if(membersElected){
            return members;
        }

        unchecked {
            for (uint i = 1; i <= TOTAL_MEMBERS; i++) {
                for (uint j = 0; j < candidateList.length - i; j++) {
                    if (
                        candidates[candidateList[j]].totalVotes >
                        candidates[candidateList[j + 1]].totalVotes
                    ) {
                        (candidateList[j], candidateList[j + 1]) = (
                            candidateList[j + 1],
                            candidateList[j]
                        );
                    }
                }
                members[i - 1] = candidateList[candidateList.length - i];
                candidates[candidateList[candidateList.length - i]]
                    .electedMember = true;
            }
        }

        membersElected = true;

        currentLeaderAddress = members[0]; // = candidateList[candidateList.length - 1] ; Highest voted candidate
        currentLeaderNumber = 0;

        candidates[currentLeaderAddress].leadershipTime = block.timestamp;

        emit ElectionResults(members, currentLeaderAddress);
        return members; 
    }

    function changeLeader() public {
        require(
            block.timestamp >=
                candidates[currentLeaderAddress].leadershipTime + LEADER_PERIOD,
            "Current leader's term not finished"
        );

        currentLeaderNumber++; 

        if (currentLeaderNumber >= members.length) currentLeaderNumber = 0; 

        currentLeaderAddress = members[currentLeaderNumber];

        candidates[currentLeaderAddress].leadershipTime = block.timestamp;
        emit LeadershipChanged(currentLeaderAddress);
    }

    // A supermajority of members can pass a bill or transfer money to an address


    function proposeBill(string calldata _provisions, Payment[] calldata _payments) external 
    returns(uint256) {
        require(candidates[msg.sender].electedMember, "Only members can propose bills");
        require(bytes(_provisions).length > 0, "Provisions required");
        require(activeBillByMember[msg.sender] == 0, "Member already has an active bill");
        activeBillByMember[msg.sender] = bills.length; 

        bills.push(Bill({
            proposer: msg.sender,
            provisions: _provisions,
            proposalTime: block.timestamp, 
            payments: _payments
        }));
        
        emit BillProposed(bills.length, msg.sender, _provisions); 
        return bills.length;
    }
    event BillProposed(uint256 indexed billId, address indexed proposer, string provisions);

    function voteForBill(uint256 billId) external
    returns(uint8){
        require(candidates[msg.sender].electedMember, "Only members can vote");
        require(billId < bills.length, "Invalid bill ID"); 
        
        Bill storage bill = bills[billId]; 
        require(bill.withdrawalTime == 0, "Bill withdrawn");
        require(!bill.memberVotingTime[msg.sender], "Already voted");

        bill.memberVotingTime[msg.sender] = block.timestamp;
        bill.yesVotes++;

        emit BillVoted(billId, msg.sender);
    
        if (bill.yesVotes >= SUPER_MAJORITY && !bill.executionTime) {
            emit BillPassed(billId); 
            bill.executionTime = block.timestamp; 
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
        require(!bill.executionTime, "Bill already executed"); 
        require(!bill.withdrawalTime, "Bill already withdrawn"); 
        
        bill.withdrawalTime = block.timestamp;
        activeBillByMember[msg.sender] = 0; 
        
        emit BillWithdrawn(billId); 
    }
    event BillWithdrawn(uint256 indexed billId);

    function _executeBill(uint256 billId) internal {
        Bill storage bill = bills[billId];
        for(uint256 i; i<bill.payments.length; i++){
            Payment storage payment = bill.payments[i];
            payable(payment.recipient).transfer(payment.amount);
        }
    }

    function getBillInfo(uint256 billId) external view 
        returns (Bill memory)
    {
        require(billId < bills.length, "Invalid bill ID");
        return bills[billId];
    }

    function getVotingTimeForBill(uint256 billId, address memberAddress) external view returns (uint256) {
        require(billId < bills.length, "Invalid bill ID");
        require(candidates[memberAddress].electedMember, "Not a Member");
        return bills[billId].memberVotingTime[memberAddress]; 
    }

    function getMemberActiveBill(address memberAddress) external view returns (uint256) {
        require(candidates[memberAddress].electedMember, "Not a Member");
        return activeBillByMember[memberAddress];
    }

    function proposeConstitution(
        string calldata description,
        string calldata draft,
        string calldata code,
        string calldata proposer,
        bytes32 hashedOffChain,
        string calldata supportingMaterials
    ) public payable {
        require(getCurrentPhase() == Phase.Governance, "Wrong phase");
        require(bytes(description).length > 0, "Description required");
        require(bytes(draft).length > 0, "Draft required");
        require(bytes(proposer).length > 0, "Proposer required");
        require(msg.value >= SUBMISSION_FEE, "Insufficient submission fee");

        bytes32 hashedOnChain = keccak256(
            abi.encodePacked(description, code, draft, proposer)
        );

        require(hashedOnChain == hashedOffChain, "Incorrect Hash!");

        proposals.push(
            ConstitutionProposal({
                description: description,
                draft: draft,
                code: code,
                proposer: proposer,
                hashedOffChain: hashedOffChain,
                supportingMaterials: supportingMaterials,
                submissionTime: block.timestamp,
                totalVotes: 0
            })
        );

        emit NewProposal(
            proposals.length - 1, // proposalId
            description,
            draft,
            code,
            proposer,
            supportingMaterials
        );
    }

    // members can hire and fire registrars

    function getRegistrar4VoterHash(bytes32 voterHash) public returns (address){
        return registrarVoterHashes[voterHash];
    }

    function getVoterStatus(address voterAddress) public returns (uint256){
        return referendumVotingTime[voterAddress]; 
    }

    // Registrars are randomly assigned to voters. 
    // offchain/frontend: voterHashes[i] = hash(FirstName+LastName+DoB(YYYY/MM/DD)+SSN) 
    function registerVoterBatch(
        bytes32[VOTER_BATCH] calldata voterHashes,      // 10 voter hashes in any order
        address[VOTER_BATCH] calldata voterAddresses    // 10 voter addresses in any order
        ) public {
        require(msg.sender == currentLeaderAddress, "Not authorized to add"); 
        require(getCurrentPhase() == Phase.Governance, "Wrong phase"); 
        require(voterHashes.length == VOTER_BATCH && voterAddresses.length == VOTER_BATCH, "Incorrect batch size");

        // Check all hashes are new
        for(uint8 i = 0; i < VOTER_BATCH; i++) {
            require(registrarVoterHashes[voterHashes[i]] == address(0), "Voter already registered");
            registrarVoterHashes[voterHashes[i]] = msg.sender; 
        }

        // Enable voting for all addresses
        for(uint8 i = 0; i < VOTER_BATCH; i++) { 
            require(voterAddresses[i] != address(0), "Invalid voter address"); 
            require(referendumVotingTime[voterAddresses[i]] == 0, "Addresss already registered. Registrar ERROR!"); 
            referendumVotingTime[voterAddresses[i]] = 1; 
        }

        referendumVoterCount += VOTER_BATCH; 

        emit VoterRegistered(voterAddresses, msg.sender, referendumVoterCount);
    }
    // Multiple Registrars required for registration

    function startReferendum() public {
        require(
            electionEnd + GOVERNANCE_LENGTH < block.timestamp,
            "Cannot start referendum yet"
        );

        require(proposals.length > MINIMUM_PROPOSALS, "Not enough proposals");

        require(referendumVoterCount >= MINIMUM_VOTERS, "Not enough voters");

        referendumEndTime = block.timestamp;

        emit ReferendumStarted();
    }

    function voteInReferendum(uint256[] calldata _proposals) public {
        require(block.timestamp < referendumEndTime, "Not in Referendum time");
        require(_proposals.length <= proposals.length, "Invalid vote count");
        require(
            referendumVotingTime[msg.sender] == 1,
            "Already voted or not registered"
        );

        bool[] memory votedForProposal = new bool[](proposals.length);

        for (uint i = 0; i < _proposals.length; i++) {
            uint256 _proposalId = _proposals[i];
            require(_proposalId < proposals.length, "Invalid proposal");

            if (!votedForProposal[_proposalId]) {
                votedForProposal[_proposalId] = true;
                proposals[_proposalId].totalVotes++;
            }
        }

        referendumVotingTime[msg.sender] = block.timestamp;
        emit VoteCastReferendum(msg.sender, _proposals);
    }

    function countVotesReferendum() public returns (uint256) {
        require(
            referendumEndTime > 0 && referendumEndTime < block.timestamp,
            "Call once after Referendum"
        );

        if (ratifiedConstitutionId > 0) return ratifiedConstitutionId;

        uint256 winningProposalId;
        uint256 maxVotes = 0;

        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].totalVotes > maxVotes) {
                maxVotes = proposals[i].totalVotes;
                winningProposalId = i;
            }
        }

        ratifiedConstitutionId = winningProposalId;

        ConstitutionProposal memory winner = proposals[winningProposalId];

        emit ConstitutionRatified(
            winningProposalId,
            maxVotes,
            winner.description,
            winner.draft,
            winner.code,
            winner.proposer,
            winner.supportingMaterials
        );

        return winningProposalId;
    }

    /**
     * @notice Returns contract balance
     * @dev The contract balance is publicly visible on-chain
     * @return balance Current contract balance
     */

    function treasuryReserve() public view returns (uint256) {
        return address(this).balance;
    }

    function proposeRate(uint256 newRate) external {
        require(candidates[msg.sender].electedMember, "Only members can propose");
        require(newRate <= 5000, "Rate cannot exceed 50%"); // Max 50% APR in basis points
        
        uint256 oldRate;
        uint8 oldRank = memberRank[msg.sender];

        if(!oldRank && sortedRates[oldRank].member != msg.sender) {
            numberOfRates++; 
            oldRate = 0;
        }else{
            oldRate = sortedRates[oldRank].rate;
        }

        uint8 newRank = oldRank;

        if (newRate == oldRate){
            return;
        } else if (newRate > oldRate) {
            // Move rates down
            while(newRank < TOTAL_MEMBERS - 1 && newRate > sortedRates[newRank+1].rate){ 
                sortedRates[newRank] = sortedRates[newRank + 1]; 
                memberRank[sortedRates[newRank].member] = newRank; // null if no member??
                newRank++; 
            } 
        } else { //(newRate < oldRate)
            // Move rates up
            while(newRank > 0  && newRate < sortedRates[newRank-1].rate){ 
                sortedRates[newRank] = sortedRates[newRank - 1]; 
                memberRank[sortedRates[newRank].member] = newRank; 
                newRank--; 
            } 
        } 

        sortedRates[newRank] = MemberRate ({
                                        member: msg.sender,
                                        rate: newRate}) ;
        memberRank[msg.sender] = newRank;

        emit MemberRateChanged(msg.sender, oldRate, oldRank, newRate, newRank);     

        // Check if median changes
        if (currentRate != sortedRates[MEDIAN_MEMBER].rate) {
            currentRate = sortedRates[MEDIAN_MEMBER].rate;
            interestPeriods.push(InterestPeriod({
                rate: currentRate,
                startTime: block.timestamp
            }));

            emit InterestRateUpdated(currentRate);
        }  
    }

    //   receive() external payable {
    function lend() external payable {
        Loan memory newLoan = Loan({
            amount: msg.value,
            timestamp: block.timestamp
        });

        loansByLender[msg.sender].push(newLoan);
        emit LoanReceived(msg.sender, msg.value);
    }
    
    function getBalance() external returns (uint) {

        uint _principal = bank[msg.sender].principal;
        uint _seconds = block.timestamp - bank[msg.sender].depositTime

        // formula for continuous compounding interest rate: exp(r*t)
        _balance = _principal * 2.7183 ** (interestRate/100 * _seconds /3600/24/365);

        _balance = _principal; //* (1 + interestRate/100) ** (_seconds);

        // Calculate balance based on pay rate and elapsed time since last withdrawal

        uint logr = 1000000*ln(1 + interestRate/100) / ln(2);
        _balance = _principal * 2 ** (logr * _seconds /3600/24/365 /1000000);

        payees[msg.sender].payBalance +=
            payees[msg.sender].payRate *
            (block.timestamp - payees[msg.sender].resetTime);

        payees[msg.sender].resetTime = block.timestamp;

        if (withdraw) {
        	payees[msg.sender].payBalance = _balance;
        	// bank[msg.sender].principal = 0;
        	// payable(msg.sender).transfer(payees[msg.sender].balance);

        	// Branch(main).pay(_balance);
        }

        return payees[msg.sender].payBalance;
    }
}
