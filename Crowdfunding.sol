// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Crowdfund {
    uint public totalCampaigns;
    bool private locked;

    struct Campaign {
        uint campaignId;
        address payable campaignCreator;
        string title;
        string description;
        uint targetAmount;
        uint deadlineTimestamp;
        uint totalContributed;
        bool hasClaimed;
        mapping(address => uint) contributions;
    }

    mapping(uint => Campaign) public campaigns;
    mapping(uint => address[]) public campaignContributors;

    event CampaignCreated(uint campaignId, address indexed creator, uint goalAmount, uint deadline);
    event ContributionMade(uint campaignId, address indexed contributor, uint amount);
    event FundsClaimed(uint campaignId, address indexed creator);
    event ContributionRefunded(uint campaignId, address indexed contributor, uint amount);

    modifier onlyCampaignCreator(uint _campaignId) {
        require(msg.sender == campaigns[_campaignId].campaignCreator, "Not the campaign creator");
        _;
    }

    modifier campaignIsActive(uint _campaignId) {
        require(block.timestamp < campaigns[_campaignId].deadlineTimestamp, "Campaign deadline passed");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrancy detected");
        locked = true;
        _;
        locked = false;
    }

    function launchCampaign(
        string memory _title,
        string memory _description,
        uint _targetAmount,
        uint _durationInDays
    ) external {
        require(_targetAmount > 0, "Target must be greater than 0");
        require(_durationInDays > 0 && _durationInDays <= 365, "Duration must be 1-365 days");

        totalCampaigns++;
        uint newId = totalCampaigns;

        Campaign storage newCampaign = campaigns[newId];
        newCampaign.campaignId = newId;
        newCampaign.campaignCreator = payable(msg.sender);
        newCampaign.title = _title;
        newCampaign.description = _description;
        newCampaign.targetAmount = _targetAmount;
        newCampaign.deadlineTimestamp = block.timestamp + (_durationInDays * 1 days);

        emit CampaignCreated(newId, msg.sender, _targetAmount, newCampaign.deadlineTimestamp);
    }

    function contributeToCampaign(uint _campaignId) external payable campaignIsActive(_campaignId) {
        require(msg.value > 0, "Must send ETH");

        Campaign storage campaign = campaigns[_campaignId];
        if (campaign.contributions[msg.sender] == 0) {
            campaignContributors[_campaignId].push(msg.sender);
        }

        campaign.contributions[msg.sender] += msg.value;
        campaign.totalContributed += msg.value;

        emit ContributionMade(_campaignId, msg.sender, msg.value);
    }

    function claimCampaignFunds(uint _campaignId) external onlyCampaignCreator(_campaignId) nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];

        require(block.timestamp >= campaign.deadlineTimestamp, "Too early to claim");
        require(campaign.totalContributed >= campaign.targetAmount, "Target not reached");
        require(!campaign.hasClaimed, "Funds already claimed");

        campaign.hasClaimed = true; // Effects

        uint amount = campaign.totalContributed;
        (bool sent, ) = campaign.campaignCreator.call{value: amount}(""); // Interactions
        require(sent, "Transfer failed");

        emit FundsClaimed(_campaignId, msg.sender);
    }

    function requestRefund(uint _campaignId) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        require(block.timestamp >= campaign.deadlineTimestamp, "Campaign still active");
        require(campaign.totalContributed < campaign.targetAmount, "Campaign was successful");

        uint contributedAmount = campaign.contributions[msg.sender];
        require(contributedAmount > 0, "No contributions found");

        campaign.contributions[msg.sender] = 0; // Effects

        (bool sent, ) = msg.sender.call{value: contributedAmount}(""); // Interactions
        require(sent, "Refund failed");

        emit ContributionRefunded(_campaignId, msg.sender, contributedAmount);
    }

    function getUserContribution(uint _campaignId, address _user) external view returns (uint) {
        return campaigns[_campaignId].contributions[_user];
    }

    function getCampaignContributors(uint _campaignId) external view returns (address[] memory) {
        return campaignContributors[_campaignId];
    }
}
