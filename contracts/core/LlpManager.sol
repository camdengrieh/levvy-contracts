// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IVault.sol";
import "./interfaces/ILevLpManager.sol";
import "./interfaces/IShortsTracker.sol";
import "../tokens/interfaces/IUSDL.sol";
import "../tokens/interfaces/IMintable.sol";
import "../access/Governable.sol";

pragma solidity 0.6.12;

contract LevLpManager is ReentrancyGuard, Governable, ILevLpManager {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant USDL_DECIMALS = 18;
    uint256 public constant LLP_PRECISION = 10 ** 18;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    IVault public vault;
    IShortsTracker public shortsTracker;
    address public override usdl;
    address public levLp;

    uint256 public override cooldownDuration;
    mapping(address => uint256) public override lastAddedAt;

    uint256 public aumAddition;
    uint256 public aumDeduction;

    bool public inPrivateMode;
    uint256 public shortsTrackerAveragePriceWeight;
    mapping(address => bool) public isHandler;

    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInUsdl,
        uint256 levLpSupply,
        uint256 usdlAmount,
        uint256 mintAmount
    );

    event RemoveLiquidity(
        address account,
        address token,
        uint256 levLpAmount,
        uint256 aumInUsdl,
        uint256 levLpSupply,
        uint256 usdlAmount,
        uint256 amountOut
    );

    constructor(address _vault, address _usdl, address _levLp, address _shortsTracker, uint256 _cooldownDuration) public {
        gov = msg.sender;
        vault = IVault(_vault);
        usdl = _usdl;
        levLp = _levLp;
        shortsTracker = IShortsTracker(_shortsTracker);
        cooldownDuration = _cooldownDuration;
    }

    function setInPrivateMode(bool _inPrivateMode) external onlyGov {
        inPrivateMode = _inPrivateMode;
    }

    function setShortsTracker(IShortsTracker _shortsTracker) external onlyGov {
        shortsTracker = _shortsTracker;
    }

    function setShortsTrackerAveragePriceWeight(uint256 _shortsTrackerAveragePriceWeight) external override onlyGov {
        require(shortsTrackerAveragePriceWeight <= BASIS_POINTS_DIVISOR, "LevLpManager: invalid weight");
        shortsTrackerAveragePriceWeight = _shortsTrackerAveragePriceWeight;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    function setCooldownDuration(uint256 _cooldownDuration) external override onlyGov {
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "LevLpManager: invalid _cooldownDuration");
        cooldownDuration = _cooldownDuration;
    }

    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyGov {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    function addLiquidity(address _token, uint256 _amount, uint256 _minUsdl, uint256 _minLevLp) external override nonReentrant returns (uint256) {
        if (inPrivateMode) {
            revert("LevLpManager: action not enabled");
        }
        return _addLiquidity(msg.sender, msg.sender, _token, _amount, _minUsdl, _minLevLp);
    }

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdl,
        uint256 _minLevLp
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _addLiquidity(_fundingAccount, _account, _token, _amount, _minUsdl, _minLevLp);
    }

    function removeLiquidity(
        address _tokenOut,
        uint256 _levLpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        if (inPrivateMode) {
            revert("LevLpManager: action not enabled");
        }
        return _removeLiquidity(msg.sender, _tokenOut, _levLpAmount, _minOut, _receiver);
    }

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _levLpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _removeLiquidity(_account, _tokenOut, _levLpAmount, _minOut, _receiver);
    }

    function getPrice(bool _maximise) external view returns (uint256) {
        uint256 aum = getAum(_maximise);
        uint256 supply = IERC20(levLp).totalSupply();
        return aum.mul(LLP_PRECISION).div(supply);
    }

    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    function getAumInUsdl(bool maximise) public view override returns (uint256) {
        uint256 aum = getAum(maximise);
        return aum.mul(10 ** USDL_DECIMALS).div(PRICE_PRECISION);
    }

    function getAum(bool maximise) public view returns (uint256) {
        uint256 length = vault.allWhitelistedTokensLength();
        uint256 aum = aumAddition;
        uint256 shortProfits = 0;
        IVault _vault = vault;

        for (uint256 i = 0; i < length; i++) {
            address token = vault.allWhitelistedTokens(i);
            bool isWhitelisted = vault.whitelistedTokens(token);

            if (!isWhitelisted) {
                continue;
            }

            uint256 price = maximise ? _vault.getMaxPrice(token) : _vault.getMinPrice(token);
            uint256 poolAmount = _vault.poolAmounts(token);
            uint256 decimals = _vault.tokenDecimals(token);

            if (_vault.stableTokens(token)) {
                aum = aum.add(poolAmount.mul(price).div(10 ** decimals));
            } else {
                // add global short profit / loss
                uint256 size = _vault.globalShortSizes(token);

                if (size > 0) {
                    (uint256 delta, bool hasProfit) = getGlobalShortDelta(token, price, size);
                    if (!hasProfit) {
                        // add losses from shorts
                        aum = aum.add(delta);
                    } else {
                        shortProfits = shortProfits.add(delta);
                    }
                }

                aum = aum.add(_vault.guaranteedUsd(token));

                uint256 reservedAmount = _vault.reservedAmounts(token);
                aum = aum.add(poolAmount.sub(reservedAmount).mul(price).div(10 ** decimals));
            }
        }

        aum = shortProfits > aum ? 0 : aum.sub(shortProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);
    }

    function getGlobalShortDelta(address _token, uint256 _price, uint256 _size) public view returns (uint256, bool) {
        uint256 averagePrice = getGlobalShortAveragePrice(_token);
        uint256 priceDelta = averagePrice > _price ? averagePrice.sub(_price) : _price.sub(averagePrice);
        uint256 delta = _size.mul(priceDelta).div(averagePrice);
        return (delta, averagePrice > _price);
    }

    function getGlobalShortAveragePrice(address _token) public view returns (uint256) {
        IShortsTracker _shortsTracker = shortsTracker;
        if (address(_shortsTracker) == address(0) || !_shortsTracker.isGlobalShortDataReady()) {
            return vault.globalShortAveragePrices(_token);
        }

        uint256 _shortsTrackerAveragePriceWeight = shortsTrackerAveragePriceWeight;
        if (_shortsTrackerAveragePriceWeight == 0) {
            return vault.globalShortAveragePrices(_token);
        } else if (_shortsTrackerAveragePriceWeight == BASIS_POINTS_DIVISOR) {
            return _shortsTracker.globalShortAveragePrices(_token);
        }

        uint256 vaultAveragePrice = vault.globalShortAveragePrices(_token);
        uint256 shortsTrackerAveragePrice = _shortsTracker.globalShortAveragePrices(_token);

        return
            vaultAveragePrice
                .mul(BASIS_POINTS_DIVISOR.sub(_shortsTrackerAveragePriceWeight))
                .add(shortsTrackerAveragePrice.mul(_shortsTrackerAveragePriceWeight))
                .div(BASIS_POINTS_DIVISOR);
    }

    function _addLiquidity(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdl,
        uint256 _minLevLp
    ) private returns (uint256) {
        require(_amount > 0, "LevLpManager: invalid _amount");

        // calculate aum before buyUSDL
        uint256 aumInUsdl = getAumInUsdl(true);
        uint256 levLpSupply = IERC20(levLp).totalSupply();

        IERC20(_token).safeTransferFrom(_fundingAccount, address(vault), _amount);
        uint256 usdlAmount = vault.buyUSDL(_token, address(this));
        require(usdlAmount >= _minUsdl, "LevLpManager: insufficient USDL output");

        uint256 mintAmount = aumInUsdl == 0 ? usdlAmount : usdlAmount.mul(levLpSupply).div(aumInUsdl);
        require(mintAmount >= _minLevLp, "LevLpManager: insufficient LLP output");

        IMintable(levLp).mint(_account, mintAmount);

        lastAddedAt[_account] = block.timestamp;

        emit AddLiquidity(_account, _token, _amount, aumInUsdl, levLpSupply, usdlAmount, mintAmount);

        return mintAmount;
    }

    function _removeLiquidity(
        address _account,
        address _tokenOut,
        uint256 _levLpAmount,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        require(_levLpAmount > 0, "LevLpManager: invalid _levLpAmount");
        require(lastAddedAt[_account].add(cooldownDuration) <= block.timestamp, "LevLpManager: cooldown duration not yet passed");

        // calculate aum before sellUSDL
        uint256 aumInUsdl = getAumInUsdl(false);
        uint256 levLpSupply = IERC20(levLp).totalSupply();

        uint256 usdlAmount = _levLpAmount.mul(aumInUsdl).div(levLpSupply);
        uint256 usdlBalance = IERC20(usdl).balanceOf(address(this));
        if (usdlAmount > usdlBalance) {
            IUSDL(usdl).mint(address(this), usdlAmount.sub(usdlBalance));
        }

        IMintable(levLp).burn(_account, _levLpAmount);

        IERC20(usdl).transfer(address(vault), usdlAmount);
        uint256 amountOut = vault.sellUSDL(_tokenOut, _receiver);
        require(amountOut >= _minOut, "LevLpManager: insufficient output");

        emit RemoveLiquidity(_account, _tokenOut, _levLpAmount, aumInUsdl, levLpSupply, usdlAmount, amountOut);

        return amountOut;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "LevLpManager: forbidden");
    }
}
