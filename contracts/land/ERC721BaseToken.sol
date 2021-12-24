/* solhint-disable func-order, code-complexity */
pragma solidity 0.5.9;

import "./AddressUtils.sol";
import "./interface/ERC721TokenReceiver.sol";
import "./interface/ERC721Events.sol";
import "./SuperOperators.sol";
import "./MetaTransactionReceiver.sol";
import "./interface/ERC721MandatoryTokenReceiver.sol";

contract ERC721BaseToken is ERC721Events, SuperOperators, MetaTransactionReceiver {
    using AddressUtils for address;

    bytes4 internal constant _ERC721_RECEIVED = 0x150b7a02;
    bytes4 internal constant _ERC721_BATCH_RECEIVED = 0x4b808c46;

    bytes4 internal constant ERC165ID = 0x01ffc9a7;
    bytes4 internal constant ERC721_MANDATORY_RECEIVER = 0x5e8bf644;

    // 每个账户拥有的土地数量 1单位=1*1的土地
    mapping (address => uint256) public _numNFTPerAddress;
    // landid  = uint256(owner address)
    mapping (uint256 => uint256) public _owners;

    mapping (address => mapping(address => bool)) public _operatorsForAll;
    // tokenId ==> 被授权者 
    mapping (uint256 => address) public _operators; 

    constructor(
        address metaTransactionContract,
        address admin
    ) internal {
        _admin = admin;
        _setMetaTransactionProcessor(metaTransactionContract, true);
    }

    function _transferFrom(address from, address to, uint256 id) internal {
        _numNFTPerAddress[from]--;
        _numNFTPerAddress[to]++;
        _owners[id] = uint256(to);
        emit Transfer(from, to, id);
    }

    /**
     * @notice Return the number of Land owned by an address
     * @param owner The address to look for
     * @return The number of Land token owned by the address
     */
     //该账户拥有的land数量
    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "owner is zero address");
        return _numNFTPerAddress[owner];
    }

    // 该tokenId对应的所有者
    function _ownerOf(uint256 id) internal view returns (address) {
        return address(_owners[id]);
    }

    // 返回该tokenId的所有者地址，以及有没有被授权（有授权返回1，没授权）
    function _ownerAndOperatorEnabledOf(uint256 id) internal view returns (address owner, bool operatorEnabled) {
        uint256 data = _owners[id];
        owner = address(data);
        // 如果有授权第则data = 10000...owner_address
        //因此 data/2**255 = 1.00002左右 ，因为solidity不支持小数故为1
        //result: 有授权时operatorEnabled = true; 没授权时operatorEnabled= false
        operatorEnabled = (data / 2**255) == 1;
    }

    /**
     * @notice Return the owner of a Land
     * @param id The id of the Land
     * @return The address of the owner
     */
     // 返回该id对应的NFT的所有者
    function ownerOf(uint256 id) external view returns (address owner) {
        owner = _ownerOf(id);
        require(owner != address(0), "token does not exist");
    }

    // @param owner :这里传进来的owner已经被检查过 owner == address(_owners(id))
    function _approveFor(address owner, address operator, uint256 id) internal {
        if(operator == address(0)) {
            _owners[id] = uint256(owner); // no need to resset the operator, it will be overriden next time
        } else {
            // 2**255 其实就是将256位的二进制数组的（从左到右）第一个bit位设置为1（标志位) 100...address
            _owners[id] = uint256(owner) + 2**255; 
            // operators 是用来记录tokenid对应的被授权者
            _operators[id] = operator;
        }
        emit Approval(owner, operator, id);
    }

    /**
     * @notice Approve an operator to spend tokens on the sender behalf
     * @param sender The address giving the approval
     * @param operator The address receiving the approval
     * @param id The id of the token
     */
    function approveFor(
        address sender,
        address operator,
        uint256 id
    ) external {
        address owner = _ownerOf(id);
        // sender不能是0地址
        require(sender != address(0), "sender is zero address");
        // msg.sender == sender  > msg.sender既是该tokenid的owner
        // _metaTransactionContracts[msg.sender] > msg.sender有支持元交易的权力
        // _superOperators[msg.sender] > msg.sener有superOperators的权利
        // _operatorsForAll[sender][msg.sender] > sender授权了msg.sender
        require(
            msg.sender == sender ||
            _metaTransactionContracts[msg.sender] ||
            _superOperators[msg.sender] ||
            _operatorsForAll[sender][msg.sender],
            "not authorized to approve"
        );
        // 该tokenId的所有者需要跟我们传入的sender相等
        require(owner == sender, "owner != sender");
        _approveFor(owner, operator, id);
    }

    /**
     * @notice Approve an operator to spend tokens on the sender behalf
     * @param operator The address receiving the approval
     * @param id The id of the token
     */
    function approve(address operator, uint256 id) external {
        address owner = _ownerOf(id);
        require(owner != address(0), "token does not exist");
        require(
            owner == msg.sender ||
            _superOperators[msg.sender] ||
            _operatorsForAll[owner][msg.sender],
            "not authorized to approve"
        );
        _approveFor(owner, operator, id);
    }

    /**
     * @notice Get the approved operator for a specific token
     * @param id The id of the token
     * @return The address of the operator
     */
     //返回值：如果有授权则返回授权者的弟子，如果没有授权则返回address(0)
    function getApproved(uint256 id) external view returns (address) {
        // owner：该tokenId的所有者
        //operatorEnabled：有没有被授权
        (address owner, bool operatorEnabled) = _ownerAndOperatorEnabledOf(id);
        require(owner != address(0), "token does not exist");
        if (operatorEnabled) {
            return _operators[id];
        } else {
            return address(0);
        }
    }

    function _checkTransfer(address from, address to, uint256 id) internal view returns (bool isMetaTx) {
        // owner：该tokenId的所有者
        //operatorEnabled：有没有被授权
        (address owner, bool operatorEnabled) = _ownerAndOperatorEnabledOf(id);
        require(owner != address(0), "token does not exist");
        // 必须是tokenId所有者才可以继续往下执行
        require(owner == from, "not owner in _checkTransfer");
        require(to != address(0), "can't send to zero address");
        // 如果msg.sender！= from 且 _metaTransactionContracts[msg.sender] = true，那么isMetaTx为true ，意味着该交易时元交易
        isMetaTx = msg.sender != from && _metaTransactionContracts[msg.sender];
        if (msg.sender != from && !isMetaTx) {
            //msg.sender != from 且不是元交易
            require(
                _superOperators[msg.sender] ||
                _operatorsForAll[from][msg.sender] ||
                (operatorEnabled && _operators[id] == msg.sender),
                "not approved to transfer"
            );
        }
    }

    function _checkInterfaceWith10000Gas(address _contract, bytes4 interfaceId)
        internal
        view
        returns (bool)
    {
        bool success;
        bool result;
        // []bytes32
        bytes memory call_data = abi.encodeWithSelector(
            ERC165ID,
            interfaceId
        );
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            //data起始位置
            let call_ptr := add(0x20, call_data)
            //第一个字节存储数组长度
            let call_size := mload(call_data)

            // memory在0x40存储分配的内存空间
            let output := mload(0x40) // Find empty storage location using "free memory pointer"
            // 将将0x0存储在output对应的memory位置
            mstore(output, 0x0)
            // 
            success := staticcall(
                10000,   //gas
                _contract, // target address
                call_ptr, // calldata start
                call_size, // calldata size 
                output, // return data start
                0x20  // return data size
            ) // 32 bytes
            result := mload(output)
        }
        // (10000 / 63) "not enough for supportsInterface(...)" // consume all gas, so caller can potentially know that there was not enough gas
        assert(gasleft() > 158);
        return success && result;
    }

    /**
     * @notice Transfer a token between 2 addresses
     * @param from The sender of the token
     * @param to The recipient of the token
     * @param id The id of the token
    */
    function transferFrom(address from, address to, uint256 id) external {
        bool metaTx = _checkTransfer(from, to, id);
        _transferFrom(from, to, id);
        if (to.isContract() && _checkInterfaceWith10000Gas(to, ERC721_MANDATORY_RECEIVER)) {
            require(
                _checkOnERC721Received(metaTx ? from : msg.sender, from, to, id, ""),
                "erc721 transfer rejected by to"
            );
        }
    }

    /**
     * @notice Transfer a token between 2 addresses letting the receiver knows of the transfer
     * @param from The sender of the token
     * @param to The recipient of the token
     * @param id The id of the token
     * @param data Additional data
     */
    function safeTransferFrom(address from, address to, uint256 id, bytes memory data) public {
        bool metaTx = _checkTransfer(from, to, id);
        _transferFrom(from, to, id);
        if (to.isContract()) {
            require(
                _checkOnERC721Received(metaTx ? from : msg.sender, from, to, id, data),
                "ERC721: transfer rejected by to"
            );
        }
    }

    /**
     * @notice Transfer a token between 2 addresses letting the receiver knows of the transfer
     * @param from The send of the token
     * @param to The recipient of the token
     * @param id The id of the token
     */
    function safeTransferFrom(address from, address to, uint256 id) external {
        safeTransferFrom(from, to, id, "");
    }

    /**
     * @notice Transfer many tokens between 2 addresses
     * @param from The sender of the token
     * @param to The recipient of the token
     * @param ids The ids of the tokens
     * @param data additional data
    */
    function batchTransferFrom(address from, address to, uint256[] calldata ids, bytes calldata data) external {
        _batchTransferFrom(from, to, ids, data, false);
    }

    function _batchTransferFrom(address from, address to, uint256[] memory ids, bytes memory data, bool safe) internal {
        // 是否是原交易的标志
        bool metaTx = msg.sender != from && _metaTransactionContracts[msg.sender];
        // from即是调用者 || 元交易 || msg.sender有superOperator权限 ||  from授权了msg.sender调用自己所有token的权利
        bool authorized = msg.sender == from ||
            metaTx ||
            _superOperators[msg.sender] ||
            _operatorsForAll[from][msg.sender];

        require(from != address(0), "from is zero address");
        require(to != address(0), "can't send to zero address");

        uint256 numTokens = ids.length;
        for(uint256 i = 0; i < numTokens; i ++) {
            uint256 id = ids[i];
            // owner:所有者 operatorEnabled:是否被授权
            (address owner, bool operatorEnabled) = _ownerAndOperatorEnabledOf(id);
            
            require(owner == from, "not owner in batchTransferFrom");
            // authorized为true证明这是一笔授权操作 ，因此要判断 _operators[id] == msg.sender 
            require(authorized || (operatorEnabled && _operators[id] == msg.sender), "not authorized");
            // 改变所有权归属
            _owners[id] = uint256(to);
            emit Transfer(from, to, id);
        }
        if (from != to) {
            _numNFTPerAddress[from] -= numTokens;
            _numNFTPerAddress[to] += numTokens;
        }

        if (to.isContract() && (safe || _checkInterfaceWith10000Gas(to, ERC721_MANDATORY_RECEIVER))) {
            require(
                _checkOnERC721BatchReceived(metaTx ? from : msg.sender, from, to, ids, data),
                "erc721 batch transfer rejected by to"
            );
        }
    }

    /**
     * @notice Transfer many tokens between 2 addresses ensuring the receiving contract has a receiver method
     * @param from The sender of the token
     * @param to The recipient of the token
     * @param ids The ids of the tokens
     * @param data additional data
    */
    function safeBatchTransferFrom(address from, address to, uint256[] calldata ids, bytes calldata data) external {
        _batchTransferFrom(from, to, ids, data, true);
    }

    /**
     * @notice Check if the contract supports an interface
     * 0x01ffc9a7 is ERC-165
     * 0x80ac58cd is ERC-721
     * @param id The id of the interface
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 || id == 0x80ac58cd;
    }

    /**
     * @notice Set the approval for an operator to manage all the tokens of the sender
     * @param sender The address giving the approval
     * @param operator The address receiving the approval
     * @param approved The determination of the approval
     */
    function setApprovalForAllFor(
        address sender,
        address operator,
        bool approved
    ) external {
        require(sender != address(0), "Invalid sender address");
        require(
            msg.sender == sender ||
            _metaTransactionContracts[msg.sender] ||
            _superOperators[msg.sender],
            "not authorized to approve for all"
        );

        _setApprovalForAll(sender, operator, approved);
    }

    /**
     * @notice Set the approval for an operator to manage all the tokens of the sender
     * @param operator The address receiving the approval
     * @param approved The determination of the approval
     */
    function setApprovalForAll(address operator, bool approved) external {
        _setApprovalForAll(msg.sender, operator, approved);
    }


    function _setApprovalForAll(
        address sender,
        address operator,
        bool approved
    ) internal {
        require(
            !_superOperators[operator],
            "super operator can't have their approvalForAll changed"
        );
        _operatorsForAll[sender][operator] = approved;

        emit ApprovalForAll(sender, operator, approved);
    }

    /**
     * @notice Check if the sender approved the operator
     * @param owner The address of the owner
     * @param operator The address of the operator
     * @return The status of the approval
     */
    function isApprovedForAll(address owner, address operator)
        external
        view
        returns (bool isOperator)
    {
        return _operatorsForAll[owner][operator] || _superOperators[operator];
    }

    function _burn(address from, address owner, uint256 id) public {
        require(from == owner, "not owner");
        _owners[id] = 2**160; // cannot mint it again
        _numNFTPerAddress[from]--;
        emit Transfer(from, address(0), id);
    }

    /// @notice Burns token `id`.
    /// @param id token which will be burnt.
    function burn(uint256 id) external {
        _burn(msg.sender, _ownerOf(id), id);
    }

    /// @notice Burn token`id` from `from`.
    /// @param from address whose token is to be burnt.
    /// @param id token which will be burnt.
    function burnFrom(address from, uint256 id) external {
        require(from != address(0), "Invalid sender address");
        (address owner, bool operatorEnabled) = _ownerAndOperatorEnabledOf(id);
        // owner即是调用者 || 被授权者 || superOperator ｜｜ 被授权所有者 
        require(
            msg.sender == from ||
            _metaTransactionContracts[msg.sender] ||
            (operatorEnabled && _operators[id] == msg.sender) ||
            _superOperators[msg.sender] ||
            _operatorsForAll[from][msg.sender],
            "not authorized to burn"
        );
        _burn(from, owner, id);
    }

    function _checkOnERC721Received(address operator, address from, address to, uint256 tokenId, bytes memory _data)
        internal returns (bool)
    {
        bytes4 retval = ERC721TokenReceiver(to).onERC721Received(operator, from, tokenId, _data);
        return (retval == _ERC721_RECEIVED);
    }

    function _checkOnERC721BatchReceived(address operator, address from, address to, uint256[] memory ids, bytes memory _data)
        internal returns (bool)
    {
        bytes4 retval = ERC721MandatoryTokenReceiver(to).onERC721BatchReceived(operator, from, ids, _data);
        return (retval == _ERC721_BATCH_RECEIVED);
    }
}