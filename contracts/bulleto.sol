//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


interface IERC721 {
    
    function safeTransferFrom(address from, address to, uint256 amount) external;

}

interface IERC20 {
    
    function balanceOf(address _owner) view external  returns (uint256 balance);
    
    function transferFrom(address _from, address _to, uint256 _value) external  returns (bool success);

}

contract BclubBull {
    
    IERC20 public _token;
    IERC721 public _nftToken;
    
    struct User {
        uint256 id;
        address referrer;
        address[] referrals;
        uint256 balanceBbond;  //  user earned bbonds
        uint256 balanceBfi;   // user earned bfi
        mapping(uint8 => bool) activePlanLevel; // Which user level is active we have 8 levels
        mapping(uint8 => Matrix) ActiveMatrix; // Whcih matirx is currently active in user
    }

    struct Matrix {
        address currentReferrer;
        address[] firstLevelReferrals; // 2
        address[] secondLevelReferrals; // 4
        mapping(uint8 => address) thirdLevelReferrals; // 8
        bool blocked;
        uint256 reinvestCount;
        uint256 balanceBbond;
        uint256 refDisCount;
    }
    
    mapping(address => User) public users;
    mapping(uint256 => address) public idToAddress;
    mapping(address => uint256) public userIds;
    mapping(uint8 => uint256) public levelPrice;
    
    uint8 public constant LAST_LEVEL = 8;
    uint256 public lastUserId = 2;
    address public owner;
    uint256 public contractStartTime;
    uint256 public totalInvested;

    event Registration(
        address indexed user,
        address indexed referrer
    );
    event Reinvest(
        uint8 arrow,
        address indexed from,
        address indexed receiver,
        uint8 level,
        uint256 amount,
        uint8 matrix,
        uint256 time
    );

    event SentBondDividends(
        uint8 arrow,
        address indexed from,
        address indexed receiver,
        uint8 level,
        uint256 amount,
        uint8 matrix,
        uint256 time
    );

        constructor(address ownerAddress)  {
        
        owner = ownerAddress;  
        _token = IERC20(0xF0a0913BA2b173c1fbCa1c1b2FCFC0E3678f66a9);  // 0x99ee7F1066e8F285903e29204c26d3bb0470513e
        _nftToken = IERC721(0x88A4d2B8C47B5780708478b310423D736025231f);   // 0x8BE48DC82116566560852772d6605af40fdf0Cba
        
        contractStartTime = block.timestamp;

        users[ownerAddress].id = 1;
        
        idToAddress[1] = ownerAddress;
        userIds[ownerAddress] = 1;
        

        for (uint8 i = 1; i <= LAST_LEVEL; i++) {
            users[ownerAddress].activePlanLevel[i] = true; 
        }
        levelPrice[1] = 1; // First 5 days lvl 1 is unlimited but you can't go to next lvl
        levelPrice[2] = 2; // After 5 days if you completeted your lvl 1 then you can go to lvl 2
        levelPrice[3] = 6; // If you've completed lvl 2 and what to go to lvl 3 you have to but the nextg lvl(3) otherwise you'll be blocked from all levels
        levelPrice[4] = 24; // To keep using next and previous level you have to but the next level
        levelPrice[5] = 96;
        
    }
    
    //This one will be avalibel for web3
    function registrationExt(address referrerAddress) public  {
        registration(msg.sender, referrerAddress);
        if(_token.balanceOf(owner) >= 1e8)
        {
            _token.transferFrom(owner,msg.sender,1e8);
            users[msg.sender].balanceBfi += 1;
        }

        _nftToken.safeTransferFrom(msg.sender, owner, 1);
        totalInvested ++;
    }
    
    function registration(address userAddress, address referrerAddress) private {
        require(!isUserExists(userAddress));
        require(isUserExists(referrerAddress));

        uint32 size;
        assembly {
            size := extcodesize(userAddress)
        }
        require(size == 0);

        users[userAddress].id = lastUserId;
        users[userAddress].referrer = referrerAddress;
        
        users[userAddress].activePlanLevel[1] = true;

        idToAddress[lastUserId] = userAddress;
        userIds[userAddress] = lastUserId;
        lastUserId++;
        
        users[referrerAddress].referrals.push(userAddress);
        
        updateMatrixReferrer(userAddress, findFreeReferrer(userAddress, 1), 1);

        emit Registration(
            userAddress,
            referrerAddress
        );
    }
    
    function buyNewLevel(uint8 level, uint256 amount) public {
        require(
            isUserExists(msg.sender)
        );
        require(
            (block.timestamp > contractStartTime + 30 days) 
            || (users[msg.sender].ActiveMatrix[level-1].reinvestCount > 0)
        );
        require(amount == levelPrice[level]);
        
        require(level > 1 && level <= 5);

        require(
            users[msg.sender].activePlanLevel[level - 1]
        );
        require(
            !users[msg.sender].activePlanLevel[level]
        );

        if (users[msg.sender].ActiveMatrix[level - 1].blocked) {
            users[msg.sender].ActiveMatrix[level - 1].blocked = false;
        }
        
        if(_token.balanceOf(owner) >= levelPrice[level]*1e8){
            _token.transferFrom(owner,msg.sender,levelPrice[level]*1e8);
            users[msg.sender].balanceBfi += levelPrice[level];
        }
            
        _nftToken.safeTransferFrom(msg.sender, owner, levelPrice[level]);
        totalInvested += levelPrice[level];

        address freeReferrer = findFreeReferrer(msg.sender, level);

        users[msg.sender].activePlanLevel[level] = true;
        updateMatrixReferrer(msg.sender, freeReferrer, level);

    }
    
    function buyNewLevelOwner(address userAddress, uint8 level) public {
        require(msg.sender == owner);

        address freeReferrer = findFreeReferrer(userAddress, level);
        
        if (users[userAddress].ActiveMatrix[level-1].blocked) {
                users[userAddress].ActiveMatrix[level-1].blocked = false;
        }

        users[userAddress].activePlanLevel[level] = true;
        updateMatrixReferrer(userAddress, freeReferrer, level);

    }

    function updateMatrixReferrer(
        address userAddress,
        address referrerAddress,
        uint8 level
    ) private {
        
        users[userAddress].ActiveMatrix[level].currentReferrer = referrerAddress;
        
        // 1st and 2nd point
        if (users[referrerAddress].ActiveMatrix[level].firstLevelReferrals.length < 2 ) { 
            users[referrerAddress].ActiveMatrix[level].firstLevelReferrals.push(userAddress);

            if (referrerAddress == owner) {
                return sendBonds(referrerAddress, userAddress, level, 2);
            }

            if(users[referrerAddress].ActiveMatrix[level].firstLevelReferrals.length == 1){
                setIncomeReflection(userAddress, users[referrerAddress].ActiveMatrix[level].currentReferrer, level, 1);
            }else{
                setIncomeReflection(userAddress, users[users[referrerAddress].ActiveMatrix[level].currentReferrer].ActiveMatrix[level].currentReferrer, level, 1);
            }
        }
        else if (
            // 3rd, 4th, 5th, 6th
            users[referrerAddress].ActiveMatrix[level].secondLevelReferrals.length < 4
        ) {
            // Direct payment reflection to partners
            setReflection(userAddress, referrerAddress, level);
            users[referrerAddress].ActiveMatrix[level].secondLevelReferrals.push(userAddress);
            return sendBonds(referrerAddress, userAddress, level, 2);
        }
        
        // 7ht, 8th, 9th, 10th, 11th, 12th, 13th, 14th
        else{
            
            updateActiveReferrerThirdLevel(userAddress, referrerAddress, level);
            
        }
    }

    function updateActiveReferrerThirdLevel(address userAddress, address referrerAddress, uint8 level) private {
        
        if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[0] == address(0)){  // Means its 7th place, we'll give investment to 1st downline
            
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[0] = userAddress;
            // In this case Admin is the reciver
            if (referrerAddress == owner) {
                return sendBonds(referrerAddress, userAddress, level, 2);
            }
            
            // First downline here
            return downlineDistribution(userAddress, referrerAddress, level);
            
        }
        
        else if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[1] == address(0)) // To give investment to 8th place
        {
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[1] = userAddress;
            // Direct payment reflection to partners 
            setReflection(userAddress, referrerAddress, level);
            return sendBonds(referrerAddress, userAddress, level, 2);
        }
        
        else if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[2] == address(0)) // To give investment to 9th place
        {
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[2] = userAddress;
            // Direct payment reflection to partners
            setReflection(userAddress, referrerAddress, level);
            return sendBonds(referrerAddress, userAddress, level, 2);
        }
        
        else if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[3] == address(0)){ // block.timestamp at 10th place we'll give payment to 2nd downline
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[3] = userAddress;
            // In this case Admin is the reciver
            if (referrerAddress == owner) {
                return sendBonds(referrerAddress, userAddress, level, 2);
            }
            //2nd downline here
            return downlineDistribution(userAddress, referrerAddress, level);
            
        }

        else if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[4] == address(0)) // To give investment to 11th place
        {
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[4] = userAddress;
            // Direct payment reflection to partners
            setReflection(userAddress, referrerAddress, level);
            return sendBonds(referrerAddress, userAddress, level, 2);
        }
        
        else if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[5] == address(0)) // To give investment to 12th place
        {
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[5] = userAddress;
            // Direct payment reflection to partners
            setReflection(userAddress, referrerAddress, level);
            return sendBonds(referrerAddress, userAddress, level, 2);
        }
        
        else if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[6] == address(0)){ // block.timestamp at 13th place we'll give data to 3nd downline
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[6] = userAddress;
            if (referrerAddress == owner) {
                
                // In this case Admin is the reciver
                return sendBonds(referrerAddress, userAddress, level, 2);
            }   
            //3rd downline here
            return downlineDistribution(userAddress, referrerAddress, level);

        }
        
        // block.timestamp 14th place and we need to reset the matrix and send investement to upline
        else{
            reinvestUser(userAddress, referrerAddress, level);
        }
        
    }
    
    function reinvestUser(address userAddress, address referrerAddress, uint8 level) private {
        
        users[referrerAddress].ActiveMatrix[level].firstLevelReferrals = new address[](0);
            users[referrerAddress].ActiveMatrix[level].secondLevelReferrals = new address[](0);
            for(uint8 i = 0 ; i < 8 ; i++){
                users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[i] = address(0);
            }
            users[referrerAddress].ActiveMatrix[level].blocked = true;
            users[referrerAddress].ActiveMatrix[level].reinvestCount++;
            users[referrerAddress].ActiveMatrix[level].refDisCount = 0;
            emit Reinvest(5, referrerAddress, userAddress, level, levelPrice[level], 2, block.timestamp);
            if (referrerAddress == owner) {
                return sendBonds(referrerAddress, userAddress, level, 2);
            }
            return updateMatrixReferrer(referrerAddress, findFreeReferrer(referrerAddress, level), level);
    }
    
    function downlineDistribution(address userAddress, address referrerAddress, uint8 level) private {
        
        for(uint256 i=users[referrerAddress].ActiveMatrix[level].refDisCount ; i<users[referrerAddress].referrals.length ; i++){
            
            if(users[users[referrerAddress].referrals[i]].activePlanLevel[level]
            && users[users[referrerAddress].referrals[i]].ActiveMatrix[level].secondLevelReferrals.length <= 2){
                users[referrerAddress].ActiveMatrix[level].refDisCount = ++i;
                return setIncomeReflection(userAddress, users[referrerAddress].referrals[--i], level, 3);
            }
        } 
        return sendBonds(owner, userAddress, level, 1);
    }
    
    function setReflection(address userAddress, address referrerAddress, uint8 level) private{
        
        for(uint256 i=0 ; i<users[referrerAddress].referrals.length ; i++){
            if(users[users[referrerAddress].referrals[i]].activePlanLevel[level]
            && users[users[referrerAddress].referrals[i]].ActiveMatrix[level].firstLevelReferrals.length == 0){
                users[users[referrerAddress].referrals[i]].ActiveMatrix[level].firstLevelReferrals.push(userAddress);
                break;
            }
        } 
    }
    
    function setIncomeReflection(address userAddress, address referrerAddress, uint8 level, uint8 arrow) private{
        
        while(true){
            if(!users[referrerAddress].ActiveMatrix[level].blocked){
                if(users[referrerAddress].ActiveMatrix[level].secondLevelReferrals.length < 4){
                    users[referrerAddress].ActiveMatrix[level].secondLevelReferrals.push(userAddress);
                    return sendBonds(referrerAddress, userAddress, level, arrow);
                }else{
                   return updateActiveReferrerThirdLevelReflection(userAddress, referrerAddress, level, arrow);
                }
            }
            referrerAddress = users[referrerAddress].ActiveMatrix[level].currentReferrer;
        }

    }
    
    function updateActiveReferrerThirdLevelReflection(address userAddress, address referrerAddress, uint8 level, uint8 arrow) private{
        
        if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[1] == address(0)) // To give investment to 8th place
        {
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[1] = userAddress;
            return sendBonds(referrerAddress, userAddress, level, arrow);
        }else if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[2] == address(0)) // To give investment to 9th place
        {
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[2] = userAddress;
            return sendBonds(referrerAddress, userAddress, level, arrow);
        }else if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[4] == address(0)) // To give investment to 11th place
        {
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[4] = userAddress;
            return sendBonds(referrerAddress, userAddress, level, arrow);
        }else if(users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[5] == address(0)) // To give investment to 12th place
        {                                                                                  
            users[referrerAddress].ActiveMatrix[level].thirdLevelReferrals[5] = userAddress;
            return sendBonds(referrerAddress, userAddress, level, arrow);
        }else{
            reinvestUser(userAddress, referrerAddress, level);
        }
    }


    function sendBonds(
        address receiver,
        address _from,
        uint8 level,
        uint8 arrow
    ) private {
        
        if(receiver == address(0)) receiver = owner;
        if(receiver != address(0) && receiver != owner) 
        {
            if(level < 6){
                _nftToken.safeTransferFrom(owner, receiver, levelPrice[level]);
            }
        }
        users[receiver].balanceBbond += levelPrice[level];
        users[receiver].ActiveMatrix[level].balanceBbond += levelPrice[level];
        
        emit SentBondDividends(arrow, _from, receiver, level, levelPrice[level], 2, block.timestamp);
    
    }
    
    function findFreeReferrer(address userAddress, uint8 level)
        public
        view
        returns (address)
    {
        while (true) {
            
            if (users[users[userAddress].referrer].activePlanLevel[level] 
            && !users[users[userAddress].referrer].ActiveMatrix[level].blocked) {
                return users[userAddress].referrer;
            }

            userAddress = users[userAddress].referrer;
        }
    }
    
    function getUserMatrix(address userAddress, uint8 level)
        public
        view
        returns (
            address currentReferrer,
            address[] memory firstLevelReferrals,
            address[] memory secondLevelReferrals,
            bool blocked,
            uint256 reinvestCount,
            uint256 balanceBbond
        )
    {
        Matrix storage m = (users[userAddress].ActiveMatrix[level]);
        return (
            m.currentReferrer,
            m.firstLevelReferrals,
            m.secondLevelReferrals,
            m.blocked,
            m.reinvestCount,
            m.balanceBbond
        );
    }
    
    function getUserActiveLevel(address userAddress, uint8 level) public view returns(bool){
        return users[userAddress].activePlanLevel[level];
    }
    
    function getUserThirdLevelReferrals(address userAddress, uint8 level, uint8 index) public view returns(address){
        return users[userAddress].ActiveMatrix[level].thirdLevelReferrals[index];
    }
    
    function getUserThirdLevelReferralsCount(address userAddress, uint8 level) public view returns(uint8){
        uint8 count;
        for(uint8 i=0 ; i<8 ; i++){
            if(users[userAddress].ActiveMatrix[level].thirdLevelReferrals[i] != address(0)){
                count++;
            }
        }
        return count;
    }
    
    function isUserExists(address user) public view returns (bool) {
        return (users[user].id != 0);
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