pragma solidity 0.4.16;

import "./04.Guard.sol";

contract GuardRegistry {
    mapping(bytes32 => address) public implementations;

    address public owner;

    bytes32 public defaultImplementation; // "single-owner" ATM

    // @audit-notice: `constructor()`
    function GuardRegistry() public {
        owner = msg.sender;
    }

    // register a new guard implementation, optionally setting it to the default
    function registerGuardImplementation(address impl, bool def) public {
        // @audit-info: typical `onlyOwner` function
        require(msg.sender == owner);

        // "single-owner" for `SingleOwnerGuard`
        bytes32 id = GuardIdGetter(impl).id();

        implementations[id] = impl;

        if (def) {
            defaultImplementation = id;
        }
    }

    // transfer ownership to a new address
    function transferOwnership(address newOwner) public {
        // @audit-info: typical `onlyOwner` function
        require(msg.sender == owner);

        owner = newOwner;
    }
}
