pragma solidity 0.4.16;

// @audit-info: a basic contract containing constants (fused into its bytecode)
contract GuardConstants {
    uint8 internal constant NO_ERROR = 0;
    uint8 internal constant PERMISSION_DENIED = 1;
}
