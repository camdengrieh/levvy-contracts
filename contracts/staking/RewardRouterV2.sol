// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWKLAY.sol";
import "../core/interfaces/ILevLpManager.sol";
import "../access/Governable.sol";

contract RewardRouterV2 is ReentrancyGuard, Governable {
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

    address public levvyVester;
    address public levLpVester;

    mapping (address => address) public pendingReceivers;

    event StakeLevvy(address account, address token, uint256 amount);
    event UnstakeLevvy(address account, address token, uint256 amount);

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
        address _levLpManager,
        address _levvyVester,
        address _levLpVester
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

        levvyVester = _levvyVester;
        levLpVester = _levLpVester;
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
        _unstakeLevvy(msg.sender, levvy, _amount, true);
    }

    function unstakeEsLevvy(uint256 _amount) external nonReentrant {
        _unstakeLevvy(msg.sender, esLevvy, _amount, true);
    }

    function mintAndStakeLevLp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minLevLp) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 levLpAmount = ILevLpManager(levLpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdg, _minLevLp);
        IRewardTracker(feeLevLpTracker).stakeForAccount(account, account, levLp, levLpAmount);
        IRewardTracker(stakedLevLpTracker).stakeForAccount(account, account, feeLevLpTracker, levLpAmount);

        emit StakeLevLp(account, levLpAmount);

        return levLpAmount;
    }

    function mintAndStakeLevLpKLAY(uint256 _minUsdg, uint256 _minLevLp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWKLAY(wklay).deposit{value: msg.value}();
        IERC20(wklay).approve(levLpManager, msg.value);

        address account = msg.sender;
        uint256 levLpAmount = ILevLpManager(levLpManager).addLiquidityForAccount(address(this), account, wklay, msg.value, _minUsdg, _minLevLp);

        IRewardTracker(feeLevLpTracker).stakeForAccount(account, account, levLp, levLpAmount);
        IRewardTracker(stakedLevLpTracker).stakeForAccount(account, account, feeLevLpTracker, levLpAmount);

        emit StakeLevLp(account, levLpAmount);

        return levLpAmount;
    }

    function unstakeAndRedeemLevLp(address _tokenOut, uint256 _levLpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
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

    function handleRewards(
        bool _shouldClaimLevvy,
        bool _shouldStakeLevvy,
        bool _shouldClaimEsLevvy,
        bool _shouldStakeEsLevvy,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 levvyAmount = 0;
        if (_shouldClaimLevvy) {
            uint256 levvyAmount0 = IVester(levvyVester).claimForAccount(account, account);
            uint256 levvyAmount1 = IVester(levLpVester).claimForAccount(account, account);
            levvyAmount = levvyAmount0.add(levvyAmount1);
        }

        if (_shouldStakeLevvy && levvyAmount > 0) {
            _stakeLevvy(account, account, levvy, levvyAmount);
        }

        uint256 esLevvyAmount = 0;
        if (_shouldClaimEsLevvy) {
            uint256 esLevvyAmount0 = IRewardTracker(stakedLevvyTracker).claimForAccount(account, account);
            uint256 esLevvyAmount1 = IRewardTracker(stakedLevLpTracker).claimForAccount(account, account);
            esLevvyAmount = esLevvyAmount0.add(esLevvyAmount1);
        }

        if (_shouldStakeEsLevvy && esLevvyAmount > 0) {
            _stakeLevvy(account, account, esLevvy, esLevvyAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnLevvyAmount = IRewardTracker(bonusLevvyTracker).claimForAccount(account, account);
            if (bnLevvyAmount > 0) {
                IRewardTracker(feeLevvyTracker).stakeForAccount(account, account, bnLevvy, bnLevvyAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 wklay0 = IRewardTracker(feeLevvyTracker).claimForAccount(account, address(this));
                uint256 wklay1 = IRewardTracker(feeLevLpTracker).claimForAccount(account, address(this));

                uint256 wklayAmount = wklay0.add(wklay1);
                IWKLAY(wklay).withdraw(wklayAmount);

                payable(account).sendValue(wklayAmount);
            } else {
                IRewardTracker(feeLevvyTracker).claimForAccount(account, account);
                IRewardTracker(feeLevLpTracker).claimForAccount(account, account);
            }
        }
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(IERC20(levvyVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(levLpVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(levvyVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(levLpVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedLevvy = IRewardTracker(stakedLevvyTracker).depositBalances(_sender, levvy);
        if (stakedLevvy > 0) {
            _unstakeLevvy(_sender, levvy, stakedLevvy, false);
            _stakeLevvy(_sender, receiver, levvy, stakedLevvy);
        }

        uint256 stakedEsLevvy = IRewardTracker(stakedLevvyTracker).depositBalances(_sender, esLevvy);
        if (stakedEsLevvy > 0) {
            _unstakeLevvy(_sender, esLevvy, stakedEsLevvy, false);
            _stakeLevvy(_sender, receiver, esLevvy, stakedEsLevvy);
        }

        uint256 stakedBnLevvy = IRewardTracker(feeLevvyTracker).depositBalances(_sender, bnLevvy);
        if (stakedBnLevvy > 0) {
            IRewardTracker(feeLevvyTracker).unstakeForAccount(_sender, bnLevvy, stakedBnLevvy, _sender);
            IRewardTracker(feeLevvyTracker).stakeForAccount(_sender, receiver, bnLevvy, stakedBnLevvy);
        }

        uint256 esLevvyBalance = IERC20(esLevvy).balanceOf(_sender);
        if (esLevvyBalance > 0) {
            IERC20(esLevvy).transferFrom(_sender, receiver, esLevvyBalance);
        }

        uint256 levLpAmount = IRewardTracker(feeLevLpTracker).depositBalances(_sender, levLp);
        if (levLpAmount > 0) {
            IRewardTracker(stakedLevLpTracker).unstakeForAccount(_sender, feeLevLpTracker, levLpAmount, _sender);
            IRewardTracker(feeLevLpTracker).unstakeForAccount(_sender, levLp, levLpAmount, _sender);

            IRewardTracker(feeLevLpTracker).stakeForAccount(_sender, receiver, levLp, levLpAmount);
            IRewardTracker(stakedLevLpTracker).stakeForAccount(receiver, receiver, feeLevLpTracker, levLpAmount);
        }

        IVester(levvyVester).transferStakeValues(_sender, receiver);
        IVester(levLpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(IRewardTracker(stakedLevvyTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedLevvyTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedLevvyTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedLevvyTracker.cumulativeRewards > 0");

        require(IRewardTracker(bonusLevvyTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: bonusLevvyTracker.averageStakedAmounts > 0");
        require(IRewardTracker(bonusLevvyTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: bonusLevvyTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeLevvyTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeLevvyTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeLevvyTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeLevvyTracker.cumulativeRewards > 0");

        require(IVester(levvyVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: levvyVester.transferredAverageStakedAmounts > 0");
        require(IVester(levvyVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: levvyVester.transferredCumulativeRewards > 0");

        require(IRewardTracker(stakedLevLpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedLevLpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedLevLpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedLevLpTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeLevLpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeLevLpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeLevLpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeLevLpTracker.cumulativeRewards > 0");

        require(IVester(levLpVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: levvyVester.transferredAverageStakedAmounts > 0");
        require(IVester(levLpVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: levvyVester.transferredCumulativeRewards > 0");

        require(IERC20(levvyVester).balanceOf(_receiver) == 0, "RewardRouter: levvyVester.balance > 0");
        require(IERC20(levLpVester).balanceOf(_receiver) == 0, "RewardRouter: levLpVester.balance > 0");
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

        emit StakeLevvy(_account, _token, _amount);
    }

    function _unstakeLevvy(address _account, address _token, uint256 _amount, bool _shouldReduceBnLevvy) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedLevvyTracker).stakedAmounts(_account);

        IRewardTracker(feeLevvyTracker).unstakeForAccount(_account, bonusLevvyTracker, _amount, _account);
        IRewardTracker(bonusLevvyTracker).unstakeForAccount(_account, stakedLevvyTracker, _amount, _account);
        IRewardTracker(stakedLevvyTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnLevvy) {
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
        }

        emit UnstakeLevvy(_account, _token, _amount);
    }
}
