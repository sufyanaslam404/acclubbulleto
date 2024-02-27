
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


interface IERC721 {

    function balanceOf(address owner) external view returns (uint256 balance);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function transferFrom(address from, address to, uint256 tokenId) external;

    function approve(address to, uint256 tokenId) external;

    function getApproved(uint256 tokenId) external view returns (address operator);

    function setApprovalForAll(address operator, bool _approved) external;

    function isApprovedForAll(address owner, address operator) external view returns (bool);
    
    function safeTransferFrom(address from, address to, uint256 amount) external;

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    
    function getUsedTokens(address owner, address operator) external view returns(uint256[] memory);

    function getSoldTokens(address owner) external view returns(uint256[] memory);

    function getAllTokens(address owner) external view returns(uint256[] memory);
    
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId, uint256 time);

    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

}



interface IERC20 {
    
    function balanceOf(address _owner) view external  returns (uint256 balance);
    
    function transferFrom(address _from, address _to, uint256 _value) external  returns (bool success);
    
}

interface AggregatorBfi{
    
    function getReserves() external view returns (
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
        );
        
}

contract AclubBull {
    
    IERC20 public _token;
    IERC721 public _nftToken;
    AggregatorBfi public priceFeedBfi;
    
    struct User {
        uint id;
        address referrer;
        address[] referrals;
        uint256 balanceBbond;  //  user earned bbonds
        uint256 balanceBfi;   // user earned bfi
        
        mapping(uint8 => bool) activeX6Levels;
        
        mapping(uint8 => Aclub) x6Matrix;
    }
    
    struct Aclub {
        address currentReferrer;
        address[] firstLevelReferrals;
        address[] secondLevelReferrals;
        bool blocked;
        uint reinvestCount;
        address closedPart;
        uint256 balanceBbond;
    }

    uint8 public constant LAST_LEVEL = 8;
    
    mapping(address => User) public users;
    mapping(uint => address) public idToAddress;
    mapping(address => uint) public userIds;
    mapping(address => uint) public balances; 

    uint public lastUserId = 2;
    address public owner;
    uint256 public totalInvested;
    uint256 public contractStartTime;
    
    mapping(uint8 => uint) public levelPrice;
    
    event Registration(address indexed user, address indexed referrer);
    event Reinvest(uint8 arrow, address indexed from, address indexed receiver, uint8 level, uint256 amount, uint8 matrix, uint256 time);
    event Upgrade(address indexed user, address indexed referrer, uint8 level);
    event NewUserPlace(address indexed user, address indexed referrer, uint8 level, uint8 place);
    event MissedBond(address indexed receiver, address indexed from, uint8 level);
    event SentBond(uint8 arrow, address indexed from, address indexed receiver, uint8 level, uint256 amount, uint8 matrix, uint256 time);
    
    
    constructor(address ownerAddress)  {
        
        owner = ownerAddress;
        _token = IERC20(0xF0a0913BA2b173c1fbCa1c1b2FCFC0E3678f66a9);  // 0x99ee7F1066e8F285903e29204c26d3bb0470513e
        _nftToken = IERC721(0x88A4d2B8C47B5780708478b310423D736025231f);   // 0x8BE48DC82116566560852772d6605af40fdf0Cba
        priceFeedBfi = AggregatorBfi(0x63AfbE16d677B7326D1F1322bE43E18127C80167);
        
        contractStartTime = block.timestamp;
        
        
        users[ownerAddress].id = 1;
        idToAddress[1] = ownerAddress;
        userIds[ownerAddress] = 1;
        
        for (uint8 i = 0; i <= LAST_LEVEL; i++) {
            users[ownerAddress].activeX6Levels[i] = true;
        }
        
        uint256 j = 1;
        for (uint8 i = 1; i <= LAST_LEVEL; i++) {
            levelPrice[i] = j;
            j *= 2;
        }
        
    }

    function registrationExtAclub(address referrerAddress) external {
        registration(msg.sender, referrerAddress);
    }
    
    function registration(address userAddress, address referrerAddress) private {
        require(!isUserExists(userAddress), "user exists");
        require(isUserExists(referrerAddress), "referrer not exists");
        
        uint32 size;
        assembly {
            size := extcodesize(userAddress)
        }
        require(size == 0, "cannot be a contract");
        
        User memory user = User({
            id: lastUserId,
            referrer: referrerAddress,
            referrals: new address[](0),
            balanceBbond: 0,
            balanceBfi: 0
        });
        
        users[userAddress] = user;
        idToAddress[lastUserId] = userAddress;
        
        users[userAddress].referrer = referrerAddress;
        
        users[userAddress].activeX6Levels[0] = true;
        
        
        userIds[userAddress] =lastUserId ;
        lastUserId++;
        
        users[referrerAddress].referrals.push(userAddress);

        updateX6Referrer(userAddress, findFreeAclubReferrer(userAddress, 0), 0);
        
        emit Registration(userAddress, referrerAddress);
    }
    
    function buyNewLevelAclub(uint8 level) external {
        require(isUserExists(msg.sender), "user is not exists. Register first.");
        require(level > 0 && level <= LAST_LEVEL, "invalid level");
        require(!users[msg.sender].activeX6Levels[level], "level already activated");
        if(level == 1){   
            require(
                (now > contractStartTime + 30 days) ||
                (users[msg.sender].x6Matrix[level-1].reinvestCount > 0)||
                (users[msg.sender].x6Matrix[level-1].secondLevelReferrals.length > 0),
                "Not eligible"
            );
        }else{
            require(
                (now > contractStartTime + 30 days) ||
                (users[msg.sender].x6Matrix[level-1].reinvestCount > 0),
                "Not eligible");
        }

            if (users[msg.sender].x6Matrix[level-1].blocked) {
                users[msg.sender].x6Matrix[level-1].blocked = false;
            }

            if(_token.balanceOf(owner) >= levelPrice[level]*1e8){
                if(level == 1){
                    _token.transferFrom(owner,msg.sender,2*1e8);
                    users[msg.sender].balanceBfi += 2;
                }
                else {
                    _token.transferFrom(owner,msg.sender,levelPrice[level]*1e8);
                    users[msg.sender].balanceBfi += levelPrice[level];
                    
                }
            }
           _nftToken.safeTransferFrom(msg.sender, owner, levelPrice[level]);
            totalInvested ++;
            
            users[msg.sender].activeX6Levels[level] = true;
            address freeX6Referrer = findFreeAclubReferrer(msg.sender, level);
            updateX6Referrer(msg.sender, freeX6Referrer, level);
            
            emit Upgrade(msg.sender, freeX6Referrer, level);
        
    }

    function updateX6Referrer(address userAddress, address referrerAddress, uint8 level) private {

        if (users[referrerAddress].x6Matrix[level].firstLevelReferrals.length < 2) {
            users[referrerAddress].x6Matrix[level].firstLevelReferrals.push(userAddress);
            emit NewUserPlace(userAddress, referrerAddress, level, uint8(users[referrerAddress].x6Matrix[level].firstLevelReferrals.length));
            
            //set current level
            users[userAddress].x6Matrix[level].currentReferrer = referrerAddress;

            if (referrerAddress == owner) {
                return sendBonds(referrerAddress, userAddress, level, 2);
            }
            
            address ref = users[referrerAddress].x6Matrix[level].currentReferrer;            
            users[ref].x6Matrix[level].secondLevelReferrals.push(userAddress); 
            
            uint len = users[ref].x6Matrix[level].firstLevelReferrals.length;
            
            if ((len == 2) && 
                (users[ref].x6Matrix[level].firstLevelReferrals[0] == referrerAddress) &&
                (users[ref].x6Matrix[level].firstLevelReferrals[1] == referrerAddress)) {
                if (users[referrerAddress].x6Matrix[level].firstLevelReferrals.length == 1) {
                    emit NewUserPlace(userAddress, ref, level, 5);
                } else {
                    emit NewUserPlace(userAddress, ref, level, 6);
                }
            }  else if ((len == 1 || len == 2) &&
                    users[ref].x6Matrix[level].firstLevelReferrals[0] == referrerAddress) {
                if (users[referrerAddress].x6Matrix[level].firstLevelReferrals.length == 1) {
                    emit NewUserPlace(userAddress, ref, level, 3);
                } else {
                    emit NewUserPlace(userAddress, ref, level, 4);
                }
            } else if (len == 2 && users[ref].x6Matrix[level].firstLevelReferrals[1] == referrerAddress) {
                if (users[referrerAddress].x6Matrix[level].firstLevelReferrals.length == 1) {
                    emit NewUserPlace(userAddress, ref, level, 5);
                } else {
                    emit NewUserPlace(userAddress, ref, level, 6);
                }
            }

            return updateX6ReferrerSecondLevel(userAddress, ref, level, 1);
        }
        
        users[referrerAddress].x6Matrix[level].secondLevelReferrals.push(userAddress);

        if (users[referrerAddress].x6Matrix[level].closedPart != address(0)) {
            if ((users[referrerAddress].x6Matrix[level].firstLevelReferrals[0] == users[referrerAddress].x6Matrix[level].firstLevelReferrals[1]) 
            &&
                (users[referrerAddress].x6Matrix[level].firstLevelReferrals[0] == users[referrerAddress].x6Matrix[level].closedPart)) {

                updateX6(userAddress, referrerAddress, level, true);
                return updateX6ReferrerSecondLevel(userAddress, referrerAddress, level, 2);
            } else if (users[referrerAddress].x6Matrix[level].firstLevelReferrals[0] == users[referrerAddress].x6Matrix[level].closedPart) {
                updateX6(userAddress, referrerAddress, level, true);
                return updateX6ReferrerSecondLevel(userAddress, referrerAddress, level, 2);
            } else {
                updateX6(userAddress, referrerAddress, level, false);
                return updateX6ReferrerSecondLevel(userAddress, referrerAddress, level, 2);
            }
        }

        if (users[referrerAddress].x6Matrix[level].firstLevelReferrals[1] == userAddress) {
            updateX6(userAddress, referrerAddress, level, false);
            return updateX6ReferrerSecondLevel(userAddress, referrerAddress, level, 2);
        } else if (users[referrerAddress].x6Matrix[level].firstLevelReferrals[0] == userAddress) {
            updateX6(userAddress, referrerAddress, level, true);
            return updateX6ReferrerSecondLevel(userAddress, referrerAddress, level, 2);
        }
        
        if (users[users[referrerAddress].x6Matrix[level].firstLevelReferrals[0]].x6Matrix[level].firstLevelReferrals.length <= 
            users[users[referrerAddress].x6Matrix[level].firstLevelReferrals[1]].x6Matrix[level].firstLevelReferrals.length) {
            updateX6(userAddress, referrerAddress, level, false);
        } else {
            updateX6(userAddress, referrerAddress, level, true);
        }
        
        updateX6ReferrerSecondLevel(userAddress, referrerAddress, level, 2);
    }

    function updateX6(address userAddress, address referrerAddress, uint8 level, bool x2) private {
        if (!x2) {
            users[users[referrerAddress].x6Matrix[level].firstLevelReferrals[0]].x6Matrix[level].firstLevelReferrals.push(userAddress);
            emit NewUserPlace(userAddress, users[referrerAddress].x6Matrix[level].firstLevelReferrals[0], level, uint8(users[users[referrerAddress].x6Matrix[level].firstLevelReferrals[0]].x6Matrix[level].firstLevelReferrals.length));
            emit NewUserPlace(userAddress, referrerAddress, level, 2 + uint8(users[users[referrerAddress].x6Matrix[level].firstLevelReferrals[0]].x6Matrix[level].firstLevelReferrals.length));
            //set current level
            users[userAddress].x6Matrix[level].currentReferrer = users[referrerAddress].x6Matrix[level].firstLevelReferrals[0];
        } else {
            users[users[referrerAddress].x6Matrix[level].firstLevelReferrals[1]].x6Matrix[level].firstLevelReferrals.push(userAddress);
            emit NewUserPlace(userAddress, users[referrerAddress].x6Matrix[level].firstLevelReferrals[1], level, uint8(users[users[referrerAddress].x6Matrix[level].firstLevelReferrals[1]].x6Matrix[level].firstLevelReferrals.length));
            emit NewUserPlace(userAddress, referrerAddress, level, 4 + uint8(users[users[referrerAddress].x6Matrix[level].firstLevelReferrals[1]].x6Matrix[level].firstLevelReferrals.length));
            //set current level
            users[userAddress].x6Matrix[level].currentReferrer = users[referrerAddress].x6Matrix[level].firstLevelReferrals[1];
        }
    }
    
    function updateX6ReferrerSecondLevel(address userAddress, address referrerAddress, uint8 level, uint8 arrow) private {
        if (users[referrerAddress].x6Matrix[level].secondLevelReferrals.length < 4) {
            return sendBonds(referrerAddress, userAddress, level, arrow);
        }
        
        address[] memory x6 = users[users[referrerAddress].x6Matrix[level].currentReferrer].x6Matrix[level].firstLevelReferrals;
        
        if (x6.length == 2) {
            if (x6[0] == referrerAddress ||
                x6[1] == referrerAddress) {
                users[users[referrerAddress].x6Matrix[level].currentReferrer].x6Matrix[level].closedPart = referrerAddress;
        } else if (x6.length == 1) {
                if (x6[0] == referrerAddress) {
                    users[users[referrerAddress].x6Matrix[level].currentReferrer].x6Matrix[level].closedPart = referrerAddress;
                }
            }
        }
        
        users[referrerAddress].x6Matrix[level].firstLevelReferrals = new address[](0);
        users[referrerAddress].x6Matrix[level].secondLevelReferrals = new address[](0);
        users[referrerAddress].x6Matrix[level].closedPart = address(0);

        if (!users[referrerAddress].activeX6Levels[level+1] && level != LAST_LEVEL) {
            users[referrerAddress].x6Matrix[level].blocked = true;
        }

        users[referrerAddress].x6Matrix[level].reinvestCount++;
        
        if (referrerAddress != owner) {
            address freeReferrerAddress = findFreeAclubReferrer(referrerAddress, level);

            emit Reinvest(5, referrerAddress, userAddress, level, levelPrice[level], 1, block.timestamp);
            updateX6Referrer(referrerAddress, freeReferrerAddress, level);
        } else {
            emit Reinvest(5, referrerAddress, userAddress, level, levelPrice[level], 1, block.timestamp);
            sendBonds(owner, userAddress, level, 1);
        }
    }
    
    function findFreeAclubReferrer(address userAddress, uint8 level) public view returns(address) {
        while (true) {
            if (users[users[userAddress].referrer].activeX6Levels[level]) {
                return users[userAddress].referrer;
            }
            
            userAddress = users[userAddress].referrer;
        }
    }

    function userActiveAclubLevel(address userAddress, uint8 level) public view returns(bool) {
        return users[userAddress].activeX6Levels[level];
    }

    function getUserAclubMatrix(address userAddress, uint8 level) public view 
    returns( address currentReferrer,
        address[] memory firstLevelReferrals,
        address[] memory secondLevelReferrals,
        bool blocked,
        uint256 reinvestCount,
        uint256 balanceBbond)
    {
        return (users[userAddress].x6Matrix[level].currentReferrer,
                users[userAddress].x6Matrix[level].firstLevelReferrals,
                users[userAddress].x6Matrix[level].secondLevelReferrals,
                users[userAddress].x6Matrix[level].blocked,
                users[userAddress].x6Matrix[level].reinvestCount,
                users[userAddress].x6Matrix[level].balanceBbond);
    }
    
    function isUserExists(address user) public view returns (bool) {
        return (users[user].id != 0);
    }

    function findBondReceiver(address userAddress, address _from, uint8 level) private returns(address) {
        address receiver = userAddress;
        bool isExtraDividends;
        
            while (true) {
                if (users[receiver].x6Matrix[level].blocked) {
                    emit MissedBond(receiver, _from, level);
                    isExtraDividends = true;
                    receiver = users[receiver].x6Matrix[level].currentReferrer;
                } else {
                    return receiver;
                }
            }
        
    }

    function sendBonds(address userAddress, address _from, uint8 level, uint8 arrow) private {
        
        if(level > 0 )
        {
            address receiver= findBondReceiver(userAddress, _from, level);
        
            if(receiver != owner){
                _nftToken.safeTransferFrom(owner, receiver, levelPrice[level]);
            }
            users[receiver].balanceBbond += levelPrice[level];
            users[receiver].x6Matrix[level].balanceBbond += levelPrice[level];
                    
            emit SentBond(arrow, _from, receiver, level, levelPrice[level], 1, block.timestamp);
        }

    }
    
    function getLatestPriceBfi() public view returns(uint256){
        (uint112 reserve0, uint112 reserve1,) = priceFeedBfi.getReserves();
        uint256 price = (reserve0/(1e10))/(reserve1/(1e8));
        return price;
    }
    
    function bytesToAddress(bytes memory bys) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 20))
        }
    }
    
    function isDirect(address userAddress, address referralAddress) public view returns(bool){
        for(uint256 i=0 ; i<users[userAddress].referrals.length ; i++){
            if(users[userAddress].referrals[i] == referralAddress) return true;
        }
        return false;
    }
    
    function getUserRefCount(address userAddress) public view returns(address[] memory){
        return users[userAddress].referrals;
    }
    
    
}