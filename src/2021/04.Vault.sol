pragma solidity 0.4.16;

import "./04.GuardConstants.sol";
import "./04.GuardRegistry.sol";
import "./04.Guard.sol";

// basic partial ERC20 interface
contract ERC20Like {
    function transfer(address dst, uint qty) public returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint qty
    ) public returns (bool);
}

// @audit-info: for more on this EIP, checkout: https://eips.ethereum.org/EIPS/eip-1167
contract EIP1167Factory {
    // create eip-1167 clone
    function createClone(address target) internal returns (address result) {
        // internally an `address` is acutally represented as `bytes20`
        bytes20 targetBytes = bytes20(target);

        // @audit-info: keep in mind that the free memory pointer is not updated
        assembly {
            let clone := mload(0x40) // clone: free memory pointer

            // store `0x3d60...0000` in the free memory pointer
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )

            // store 20 bytes address right after the non-zero higher-order bits in the `clone` memory slot
            mstore(add(clone, 0x14), targetBytes)

            // store `0x5af4...0000` right after the 20 bytes address
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )

            //                               |<< ------------------------------------- Standard EIP1167 Implementaion (runtime code) ------------------------------------ >>|
            // |0x--|: 0x3d602d80600a3d3981f3363d3d373d3d3d363d73 (20 bytes) |0x94| 0000000000000000000000000000000000000000 (20 bytes) |0xa8| 5af43d82803e903d91602b57fd5bf3
            //         |<< --------- initcode start --------- >>|                   |<< ------- `target` address ------- >>|                   |<< ---- initcode end ---- >>|

            result := create(
                0, // value to send
                clone, // deploycode start (OFFSET)
                0x37 // deploycode length (55)
            )
        }
    }
}

contract Vault is GuardConstants, EIP1167Factory {
    // @audit-info:                                                 STORAGE LAYOUT
    address public owner; //                                                  0x00
    address public pendingOwner; //                                           0x01

    GuardRegistry public registry; //                                         0x02

    Guard public guard; //                                                    0x03

    mapping(address => mapping(address => uint)) public balances; //          0x04

    // @audit-notice: `constructor()`
    function Vault(GuardRegistry registry_) public {
        owner = msg.sender;
        registry = registry_;

        createGuard(registry.defaultImplementation());
    }

    // create new guard instance
    function createGuard(bytes32 implementation) private returns (Guard) {
        // `impl` is an instance of SingleOwnerGuard
        address impl = registry.implementations(implementation);
        require(impl != address(0x00));

        // calling `createGuard` in the `constructor()` above skips this block
        if (address(guard) != address(0x00)) {
            guard.cleanup();
        }

        // when `Setup` is running, this is set to a proxy of a `SingleOwnerGuard` implementation
        guard = Guard(createClone(impl));
        guard.initialize(this);
        return guard;
    }

    // check access
    function checkAccess(string memory op) private returns (bool) {
        uint8 error;
        (error, ) = guard.isAllowed(msg.sender, op);

        // @audit-notice: This only checks that no error is thrown. it doesn't validate if the guard's `owner()` is the msg.sender
        return error == NO_ERROR;
    }

    // update the guard implementation
    // @audit-info: callable only by the `vault.owner()` because `Setup` doesn't add "updateGuard" public operation
    function updateGuard(bytes32 impl) public returns (Guard) {
        require(checkAccess("updateGuard"));

        return createGuard(impl);
    }

    // deposit tokens
    function deposit(ERC20Like tok, uint amnt) public {
        require(checkAccess("deposit"));

        require(tok.transferFrom(msg.sender, address(this), amnt));

        balances[msg.sender][address(tok)] += amnt;
    }

    // withdraw tokens
    function withdraw(ERC20Like tok, uint amnt) public {
        require(checkAccess("withdraw"));

        require(balances[msg.sender][address(tok)] >= amnt);

        tok.transfer(msg.sender, amnt);

        balances[msg.sender][address(tok)] -= amnt;
    }

    // rescue stuck tokens
    // @audit-info: this function can be an access point for an exploit but it's protected by being callable by the `owner()`
    function emergencyCall(address target, bytes memory data) public {
        require(checkAccess("emergencyCall"));

        require(target.delegatecall(data));
    }

    // transfer ownership to a new address
    function transferOwnership(address newOwner) public {
        require(msg.sender == owner);

        pendingOwner = newOwner;
    }

    // accept the ownership transfer
    function acceptOwnership() public {
        require(msg.sender == pendingOwner);

        owner = pendingOwner;
        pendingOwner = address(0x00);
    }
}

// I'm thinking to create a malicious contract that implements `ERC20Like` that executes arbirary code when `transferFrom()` or `transfer()` is called
// Is it possible for me to `initialize()` the implementation contract used by `guard` and cause malicious things to happen?
// can I manipulate the `returndatasize()` that `guard.isAllowed(msg.sender, op)` uses internally to manipulate it's return value?
