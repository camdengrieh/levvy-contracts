// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";

import "../core/interfaces/ILevLpManager.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardTracker.sol";

// provide a way to transfer staked LLP tokens by unstaking from the sender
// and staking for the receiver
// tests in RewardRouterV2.js
contract StakedLevLp {
    using SafeMath for uint256;

    string public constant name = "StakedLevLp";
    string public constant symbol = "sLLP";
    uint8 public constant decimals = 18;

    address public levLp;
    ILevLpManager public levLpManager;
    address public stakedLevLpTracker;
    address public feeLevLpTracker;

    mapping(address => mapping(address => uint256)) public allowances;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(address _levLp, ILevLpManager _levLpManager, address _stakedLevLpTracker, address _feeLevLpTracker) public {
        levLp = _levLp;
        levLpManager = _levLpManager;
        stakedLevLpTracker = _stakedLevLpTracker;
        feeLevLpTracker = _feeLevLpTracker;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "StakedLevLp: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function balanceOf(address _account) external view returns (uint256) {
        return IRewardTracker(feeLevLpTracker).depositBalances(_account, levLp);
    }

    function totalSupply() external view returns (uint256) {
        return IERC20(stakedLevLpTracker).totalSupply();
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "StakedLevLp: approve from the zero address");
        require(_spender != address(0), "StakedLevLp: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "StakedLevLp: transfer from the zero address");
        require(_recipient != address(0), "StakedLevLp: transfer to the zero address");

        require(
            levLpManager.lastAddedAt(_sender).add(levLpManager.cooldownDuration()) <= block.timestamp,
            "StakedLevLp: cooldown duration not yet passed"
        );

        IRewardTracker(stakedLevLpTracker).unstakeForAccount(_sender, feeLevLpTracker, _amount, _sender);
        IRewardTracker(feeLevLpTracker).unstakeForAccount(_sender, levLp, _amount, _sender);

        IRewardTracker(feeLevLpTracker).stakeForAccount(_sender, _recipient, levLp, _amount);
        IRewardTracker(stakedLevLpTracker).stakeForAccount(_recipient, _recipient, feeLevLpTracker, _amount);
    }
}
