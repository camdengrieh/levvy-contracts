// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWKLAY.sol";
import "../core/interfaces/ILevLpManager.sol";
import "../access/Governable.sol";

contract RewardRouter is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public wklay;

    address public levvy;
    address public esLevvy;
    address public bnLevvy;

    address public levLp; // LEV Liquidity Provider token

    address public stakedLevvyTracker;
    address public bonusLevvyTracker;
    address public feeLevvyTracker;

    address public stakedLevLpTracker;
    address public feeLevLpTracker;

    address public levLpManager;

    event StakeLevvy(address account, uint256 amount);
    event UnstakeLevvy(address account, uint256 amount);

    event StakeLevLp(address account, uint256 amount);
    event UnstakeLevLp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == wklay, "Router: invalid sender");
    }

    function initialize(
        address _wklay,
        address _levvy,
        address _esLevvy,
        address _bnLevvy,
        address _levLp,
        address _stakedLevvyTracker,
        address _bonusLevvyTracker,
        address _feeLevvyTracker,
        address _feeLevLpTracker,
        address _stakedLevLpTracker,
        address _levLpManager
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        wklay = _wklay;

        levvy = _levvy;
        esLevvy = _esLevvy;
        bnLevvy = _bnLevvy;

        levLp = _levLp;

        stakedLevvyTracker = _stakedLevvyTracker;
        bonusLevvyTracker = _bonusLevvyTracker;
        feeLevvyTracker = _feeLevvyTracker;

        feeLevLpTracker = _feeLevLpTracker;
        stakedLevLpTracker = _stakedLevLpTracker;

        levLpManager = _levLpManager;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeLevvyForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _levvy = levvy;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeLevvy(msg.sender, _accounts[i], _levvy, _amounts[i]);
        }
    }

    function stakeLevvyForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeLevvy(msg.sender, _account, levvy, _amount);
    }

    function stakeLevvy(uint256 _amount) external nonReentrant {
        _stakeLevvy(msg.sender, msg.sender, levvy, _amount);
    }

    function stakeEsLevvy(uint256 _amount) external nonReentrant {
        _stakeLevvy(msg.sender, msg.sender, esLevvy, _amount);
    }

    function unstakeLevvy(uint256 _amount) external nonReentrant {
        _unstakeLevvy(msg.sender, levvy, _amount);
    }

    function unstakeEsLevvy(uint256 _amount) external nonReentrant {
        _unstakeLevvy(msg.sender, esLevvy, _amount);
    }

    function mintAndStakeLevLp(address _token, uint256 _amount, uint256 _minUsdl, uint256 _minLevLp) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 levLpAmount = ILevLpManager(levLpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdl, _minLevLp);
        IRewardTracker(feeLevLpTracker).stakeForAccount(account, account, levLp, levLpAmount);
        IRewardTracker(stakedLevLpTracker).stakeForAccount(account, account, feeLevLpTracker, levLpAmount);

        emit StakeLevLp(account, levLpAmount);

        return levLpAmount;
    }

    function mintAndStakeLevLpKLAY(uint256 _minUsdl, uint256 _minLevLp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWKLAY(wklay).deposit{value: msg.value}();
        IERC20(wklay).approve(levLpManager, msg.value);

        address account = msg.sender;
        uint256 levLpAmount = ILevLpManager(levLpManager).addLiquidityForAccount(address(this), account, wklay, msg.value, _minUsdl, _minLevLp);

        IRewardTracker(feeLevLpTracker).stakeForAccount(account, account, levLp, levLpAmount);
        IRewardTracker(stakedLevLpTracker).stakeForAccount(account, account, feeLevLpTracker, levLpAmount);

        emit StakeLevLp(account, levLpAmount);

        return levLpAmount;
    }

    function unstakeAndRedeemLevLp(
        address _tokenOut,
        uint256 _levLpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_levLpAmount > 0, "RewardRouter: invalid _levLpAmount");

        address account = msg.sender;
        IRewardTracker(stakedLevLpTracker).unstakeForAccount(account, feeLevLpTracker, _levLpAmount, account);
        IRewardTracker(feeLevLpTracker).unstakeForAccount(account, levLp, _levLpAmount, account);
        uint256 amountOut = ILevLpManager(levLpManager).removeLiquidityForAccount(account, _tokenOut, _levLpAmount, _minOut, _receiver);

        emit UnstakeLevLp(account, _levLpAmount);

        return amountOut;
    }

    function unstakeAndRedeemLevLpKLAY(uint256 _levLpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_levLpAmount > 0, "RewardRouter: invalid _levLpAmount");

        address account = msg.sender;
        IRewardTracker(stakedLevLpTracker).unstakeForAccount(account, feeLevLpTracker, _levLpAmount, account);
        IRewardTracker(feeLevLpTracker).unstakeForAccount(account, levLp, _levLpAmount, account);
        uint256 amountOut = ILevLpManager(levLpManager).removeLiquidityForAccount(account, wklay, _levLpAmount, _minOut, address(this));

        IWKLAY(wklay).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeLevLp(account, _levLpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeLevvyTracker).claimForAccount(account, account);
        IRewardTracker(feeLevLpTracker).claimForAccount(account, account);

        IRewardTracker(stakedLevvyTracker).claimForAccount(account, account);
        IRewardTracker(stakedLevLpTracker).claimForAccount(account, account);
    }

    function claimEsLevvy() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedLevvyTracker).claimForAccount(account, account);
        IRewardTracker(stakedLevLpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeLevvyTracker).claimForAccount(account, account);
        IRewardTracker(feeLevLpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function _compound(address _account) private {
        _compoundLevvy(_account);
        _compoundLevLp(_account);
    }

    function _compoundLevvy(address _account) private {
        uint256 esLevvyAmount = IRewardTracker(stakedLevvyTracker).claimForAccount(_account, _account);
        if (esLevvyAmount > 0) {
            _stakeLevvy(_account, _account, esLevvy, esLevvyAmount);
        }

        uint256 bnLevvyAmount = IRewardTracker(bonusLevvyTracker).claimForAccount(_account, _account);
        if (bnLevvyAmount > 0) {
            IRewardTracker(feeLevvyTracker).stakeForAccount(_account, _account, bnLevvy, bnLevvyAmount);
        }
    }

    function _compoundLevLp(address _account) private {
        uint256 esLevvyAmount = IRewardTracker(stakedLevLpTracker).claimForAccount(_account, _account);
        if (esLevvyAmount > 0) {
            _stakeLevvy(_account, _account, esLevvy, esLevvyAmount);
        }
    }

    function _stakeLevvy(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedLevvyTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusLevvyTracker).stakeForAccount(_account, _account, stakedLevvyTracker, _amount);
        IRewardTracker(feeLevvyTracker).stakeForAccount(_account, _account, bonusLevvyTracker, _amount);

        emit StakeLevvy(_account, _amount);
    }

    function _unstakeLevvy(address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedLevvyTracker).stakedAmounts(_account);

        IRewardTracker(feeLevvyTracker).unstakeForAccount(_account, bonusLevvyTracker, _amount, _account);
        IRewardTracker(bonusLevvyTracker).unstakeForAccount(_account, stakedLevvyTracker, _amount, _account);
        IRewardTracker(stakedLevvyTracker).unstakeForAccount(_account, _token, _amount, _account);

        uint256 bnLevvyAmount = IRewardTracker(bonusLevvyTracker).claimForAccount(_account, _account);
        if (bnLevvyAmount > 0) {
            IRewardTracker(feeLevvyTracker).stakeForAccount(_account, _account, bnLevvy, bnLevvyAmount);
        }

        uint256 stakedBnLevvy = IRewardTracker(feeLevvyTracker).depositBalances(_account, bnLevvy);
        if (stakedBnLevvy > 0) {
            uint256 reductionAmount = stakedBnLevvy.mul(_amount).div(balance);
            IRewardTracker(feeLevvyTracker).unstakeForAccount(_account, bnLevvy, reductionAmount, _account);
            IMintable(bnLevvy).burn(_account, reductionAmount);
        }

        emit UnstakeLevvy(_account, _amount);
    }
}
