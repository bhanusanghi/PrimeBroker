import { MockContract } from "@defi-wonderland/smock"
import { expect } from "chai"
import { BigNumber } from "ethers"
import { parseEther, parseUnits } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import {
    BaseToken,
    ClearingHouseConfig,
    MarketRegistry,
    OrderBook,
    QuoteToken,
    TestAccountBalance,
    TestClearingHouse,
    TestERC20,
    UniswapV3Pool,
    Vault,
} from "../../typechain"
import { initAndAddPool } from "../helper/marketHelper"
import { getMaxTickRange } from "../helper/number"
import { deposit } from "../helper/token"
import { encodePriceSqrt } from "../shared/utilities"
import { ClearingHouseFixture, createClearingHouseFixture } from "./fixtures"

describe("ClearingHouse openPosition", () => {
    const [admin, maker, maker2, taker, carol] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let clearingHouseFixture: ClearingHouseFixture
    let clearingHouse: TestClearingHouse
    let marketRegistry: MarketRegistry
    let clearingHouseConfig: ClearingHouseConfig
    let orderBook: OrderBook
    let accountBalance: TestAccountBalance
    let vault: Vault
    let collateral: TestERC20
    let baseToken: BaseToken
    let baseToken2: BaseToken
    let quoteToken: QuoteToken
    let pool: UniswapV3Pool
    let pool2: UniswapV3Pool
    let mockedBaseAggregator: MockContract
    let mockedBaseAggregator2: MockContract
    let collateralDecimals: number
    const lowerTick: number = 0
    const upperTick: number = 100000

    beforeEach(async () => {
        clearingHouseFixture = await loadFixture(createClearingHouseFixture())
        clearingHouse = clearingHouseFixture.clearingHouse as TestClearingHouse
        orderBook = clearingHouseFixture.orderBook
        accountBalance = clearingHouseFixture.accountBalance as TestAccountBalance
        clearingHouseConfig = clearingHouseFixture.clearingHouseConfig
        vault = clearingHouseFixture.vault
        marketRegistry = clearingHouseFixture.marketRegistry
        collateral = clearingHouseFixture.USDC
        baseToken = clearingHouseFixture.baseToken
        baseToken2 = clearingHouseFixture.baseToken2
        quoteToken = clearingHouseFixture.quoteToken
        mockedBaseAggregator = clearingHouseFixture.mockedBaseAggregator
        mockedBaseAggregator2 = clearingHouseFixture.mockedBaseAggregator2
        pool = clearingHouseFixture.pool
        pool2 = clearingHouseFixture.pool2
        collateralDecimals = await collateral.decimals()

        mockedBaseAggregator.smocked.latestRoundData.will.return.with(async () => {
            return [0, parseUnits("151", 6), 0, 0, 0]
        })
        await initAndAddPool(
            clearingHouseFixture,
            pool,
            baseToken.address,
            encodePriceSqrt("151.373306858723226652", "1"), // tick = 50200 (1.0001^50200 = 151.373306858723226652)
            10000,
            // set maxTickCrossed as maximum tick range of pool by default, that means there is no over price when swap
            getMaxTickRange(),
        )

        mockedBaseAggregator2.smocked.latestRoundData.will.return.with(async () => {
            return [0, parseUnits("151", 6), 0, 0, 0]
        })
        await initAndAddPool(
            clearingHouseFixture,
            pool2,
            baseToken2.address,
            encodePriceSqrt("151.373306858723226652", "1"), // tick = 50200 (1.0001^50200 = 151.373306858723226652)
            10000,
            // set maxTickCrossed as maximum tick range of pool by default, that means there is no over price when swap
            getMaxTickRange(),
        )

        await marketRegistry.setFeeRatio(baseToken.address, 10000)
        await marketRegistry.setFeeRatio(baseToken2.address, 10000)

        // prepare collateral for maker
        const makerCollateralAmount = parseUnits("1000000", collateralDecimals)
        await collateral.mint(maker.address, makerCollateralAmount)
        await collateral.mint(maker2.address, makerCollateralAmount)
        await deposit(maker, vault, 1000000, collateral)
        await deposit(maker2, vault, 1000000, collateral)

        // maker add liquidity
        await clearingHouse.connect(maker).addLiquidity({
            baseToken: baseToken.address,
            base: parseEther("65.943787"),
            quote: parseEther("10000"),
            lowerTick,
            upperTick,
            minBase: 0,
            minQuote: 0,
            useTakerBalance: false,
            deadline: ethers.constants.MaxUint256,
        })

        // maker
        //   pool.base = 65.9437860798
        //   pool.quote = 10000
        //   liquidity = 884.6906588359
        //   virtual base liquidity = 884.6906588359 / sqrt(151.373306858723226652) = 71.9062751863
        //   virtual quote liquidity = 884.6906588359 * sqrt(151.373306858723226652) = 10884.6906588362

        // prepare collateral for taker
        const takerCollateral = parseUnits("1000", collateralDecimals)
        await collateral.mint(taker.address, takerCollateral)
        await collateral.connect(taker).approve(clearingHouse.address, takerCollateral)
    })

    async function getMakerFee(): Promise<BigNumber> {
        return (
            await clearingHouse.connect(maker).callStatic.removeLiquidity({
                baseToken: baseToken.address,
                lowerTick: lowerTick,
                upperTick: upperTick,
                liquidity: 0,
                minBase: 0,
                minQuote: 0,
                deadline: ethers.constants.MaxUint256,
            })
        ).fee
    }

    describe("invalid input", () => {
        describe("taker has enough collateral", () => {
            beforeEach(async () => {
                await deposit(taker, vault, 1000, collateral)
            })

            it("force error due to invalid baseToken", async () => {
                // will reverted due to function selector was not recognized (IBaseToken(baseToken).getStatus)
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: pool.address,
                        isBaseToQuote: true,
                        isExactInput: true,
                        oppositeAmountBound: 0,
                        amount: 1,
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                ).to.be.reverted
            })

            it("force error due to invalid amount (0)", async () => {
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: true,
                        isExactInput: true,
                        oppositeAmountBound: 0,
                        amount: 0,
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                ).to.be.reverted
            })

            it("force error due to slippage protection", async () => {
                // taker want to get 1 vETH in exact current price which is not possible
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: false,
                        isExactInput: false,
                        oppositeAmountBound: 0,
                        amount: 1,
                        sqrtPriceLimitX96: encodePriceSqrt("151.373306858723226652", "1"),
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                ).to.be.revertedWith("SPL")
            })

            it("force error due to not enough liquidity", async () => {
                // empty the liquidity
                const order = await orderBook.getOpenOrder(maker.address, baseToken.address, lowerTick, upperTick)
                await clearingHouse.connect(maker).removeLiquidity({
                    baseToken: baseToken.address,
                    lowerTick,
                    upperTick,
                    liquidity: order.liquidity,
                    minBase: 0,
                    minQuote: 0,
                    deadline: ethers.constants.MaxUint256,
                })

                // trade
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: false,
                        isExactInput: false,
                        oppositeAmountBound: 0,
                        amount: 1,
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                ).to.be.revertedWith("CH_F0S")
            })
        })
    })

    describe("taker has 0 collateral", () => {
        // using formula: https://www.notion.so/perp/Index-price-spread-attack-2f203d45b34f4cc3ab80ac835247030f#d3d12da52d4c455999dcca491a1ba34d
        const calcQuoteAmountForLong = (marketPrice: number, indexPrice: number, liquidity: number): number => {
            return (indexPrice * liquidity * 0.9 - marketPrice * liquidity) / Math.sqrt(marketPrice) / 10 ** 18 - 1
        }
        // using formula: https://www.notion.so/perp/Index-price-spread-attack-2f203d45b34f4cc3ab80ac835247030f#a14db12f09404b0bb43242be5a706179
        const calcQuoteAmountForShort = (marketPrice: number, indexPrice: number, liquidity: number): number => {
            return (
                (0.9 * marketPrice * liquidity - indexPrice * liquidity) / (0.9 * Math.sqrt(marketPrice)) / 10 ** 18 - 1
            )
        }
        beforeEach(async () => {
            // set fee ratio to 0
            await marketRegistry.setFeeRatio(baseToken.address, 0)
        })
        describe("market price lesser than index price", () => {
            beforeEach(async () => {
                // the index price must be larger than (market price / 0.9) = 151 / 0.9 ~= 167
                // market price = 151.373306858723226652
                // index price = 170
                // liquidity = 884690658835870366575
                mockedBaseAggregator.smocked.latestRoundData.will.return.with(async () => {
                    return [0, parseUnits("170", 6), 0, 0, 0]
                })
            })
            it("force error, Q2B, due to not enough collateral for mint", async () => {
                const quoteAmount = calcQuoteAmountForLong(
                    151.373306858723226652,
                    170,
                    884690658835870366575,
                ).toString()
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: false,
                        isExactInput: true,
                        oppositeAmountBound: 0,
                        amount: parseEther(quoteAmount),
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                ).to.be.revertedWith("CH_NEFCI")
            })

            it("force error, B2Q, due to not enough collateral for mint", async () => {
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: true,
                        isExactInput: false,
                        oppositeAmountBound: 0,
                        amount: parseEther("100"),
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                ).to.be.revertedWith("CH_NEFCI")
            })
        })

        describe("market price larger than index price", () => {
            beforeEach(async () => {
                // the index price must be lesser than (market price * 0.9) = 151 * 0.9 ~= 135.9
                // market price = 151.373306858723226652
                // index price = 133
                // liquidity = 884690658835870366575
                mockedBaseAggregator.smocked.latestRoundData.will.return.with(async () => {
                    return [0, parseUnits("133", 6), 0, 0, 0]
                })
            })
            it("force error, Q2B, due to not enough collateral for mint", async () => {
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: false,
                        isExactInput: true,
                        oppositeAmountBound: 0,
                        amount: parseEther("100"),
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                ).to.be.revertedWith("CH_NEFCI")
            })

            it("force error, B2Q, due to not enough collateral for mint", async () => {
                const quoteAmount = calcQuoteAmountForShort(
                    151.373306858723226652,
                    133,
                    884690658835870366575,
                ).toString()
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: true,
                        isExactInput: false,
                        oppositeAmountBound: 0,
                        amount: parseEther(quoteAmount),
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                ).to.be.revertedWith("CH_NEFCI")
            })
        })
    })

    describe("taker open position from zero", async () => {
        beforeEach(async () => {
            await deposit(taker, vault, 1000, collateral)
        })

        describe("long", () => {
            it("verify base and quote amount in static call", async () => {
                // taker swap 1 USD for 6539527905092835/10^18 ETH
                const response = await clearingHouse.connect(taker).callStatic.openPosition({
                    baseToken: baseToken.address,
                    isBaseToQuote: false,
                    isExactInput: true,
                    oppositeAmountBound: 0,
                    amount: parseEther("1"),
                    sqrtPriceLimitX96: 0,
                    deadline: ethers.constants.MaxUint256,
                    referralCode: ethers.constants.HashZero,
                })
                expect(response.base).to.be.eq("6539527905092835")
                expect(response.quote).to.be.eq("1000000000000000000")
            })

            it("increase ? position when exact input", async () => {
                // taker swap 1 USD for ? ETH
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: false,
                        isExactInput: true,
                        oppositeAmountBound: 0,
                        amount: parseEther("1"),
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                )
                    .to.emit(clearingHouse, "PositionChanged")
                    .withArgs(
                        taker.address, // trader
                        baseToken.address, // baseToken
                        "6539527905092835", // exchangedPositionSize
                        parseEther("-0.99"), // exchangedPositionNotional
                        parseEther("0.01"), // fee = 1 * 0.01
                        parseEther("-1"), // openNotional
                        parseEther("0"), // realizedPnl
                        "974863323923301853330898562804", // sqrtPriceAfterX96
                    )
                const [baseBalance, quoteBalance] = await clearingHouse.getTokenBalance(
                    taker.address,
                    baseToken.address,
                )
                expect(baseBalance).be.gt(parseEther("0"))
                expect(quoteBalance).be.deep.eq(parseEther("-1"))

                expect(await getMakerFee()).be.closeTo(parseEther("0.01"), 1)

                expect(await accountBalance.getTakerPositionSize(taker.address, baseToken.address)).to.be.eq(
                    "6539527905092835",
                )
            })

            it("increase 1 long position when exact output", async () => {
                // taker swap ? USD for 1 ETH -> quote to base -> fee is charged before swapping
                //   exchanged notional = 71.9062751863 * 10884.6906588362 / (71.9062751863 - 1) - 10884.6906588362 = 153.508143394
                //   taker fee = 153.508143394 / 0.99 * 0.01 = 1.550587307

                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: false,
                        isExactInput: false,
                        oppositeAmountBound: 0,
                        amount: parseEther("1"),
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                )
                    .to.emit(clearingHouse, "PositionChanged")
                    .withArgs(
                        taker.address, // trader
                        baseToken.address, // baseToken
                        parseEther("1"), // exchangedPositionSize
                        "-153508143394151325059", // exchangedPositionNotional
                        "1550587307011629547", // fee
                        "-155058730701162954606", // openNotional
                        parseEther("0"), // realizedPnl
                        "988522032908775036581348357236", // sqrtPriceAfterX96
                    )

                const [baseBalance, quoteBalance] = await clearingHouse.getTokenBalance(
                    taker.address,
                    baseToken.address,
                )
                expect(baseBalance).be.deep.eq(parseEther("1"))
                expect(quoteBalance).be.lt(parseEther("0"))

                expect(await getMakerFee()).be.closeTo(parseEther("1.550587307011629547"), 1)
            })
        })
        describe("short", () => {
            it("increase position from 0, exact input", async () => {
                // taker swap 1 ETH for ? USD -> base to quote -> fee is included in exchangedNotional
                //   taker exchangedNotional = 10884.6906588362 - 71.9062751863 * 10884.6906588362 / (71.9062751863 + 1) = 149.2970341856
                //   taker fee = 149.2970341856 * 0.01 = 1.492970341856

                // taker swap 1 ETH for ? USD
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: true,
                        isExactInput: true,
                        oppositeAmountBound: 0,
                        amount: parseEther("1"),
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                )
                    .to.emit(clearingHouse, "PositionChanged")
                    .withArgs(
                        taker.address, // trader
                        baseToken.address, // baseToken
                        parseEther("-1"), // exchangedPositionSize
                        parseEther("149.297034185732877727"), // exchangedPositionNotional
                        parseEther("1.492970341857328778"), // fee: 149.297034185732877727 * 0.01 = 1.492970341857328777
                        parseEther("147.804063843875548949"), // openNotional
                        parseEther("0"), // realizedPnl
                        "961404421142614700863221952241", // sqrtPriceAfterX96
                    )
                const [baseBalance, quoteBalance] = await clearingHouse.getTokenBalance(
                    taker.address,
                    baseToken.address,
                )

                expect(baseBalance).be.deep.eq(parseEther("-1"))
                expect(quoteBalance).be.gt(parseEther("0"))

                expect(await getMakerFee()).be.closeTo(parseEther("1.492970341857328777"), 1)
            })

            it("increase position from 0, exact output", async () => {
                // taker swap ? ETH for 1 USD -> base to quote -> fee is included in exchangedNotional
                //   taker exchangedNotional = 71.9062751863 - 71.9062751863 * 10884.6906588362 / (10884.6906588362 - 1)
                //                           = -0.006606791523
                //   taker fee = 1 / (0.99) * 0.01 = 0.0101010101

                // taker swap ? ETH for 1 USD
                await expect(
                    clearingHouse.connect(taker).openPosition({
                        baseToken: baseToken.address,
                        isBaseToQuote: true,
                        isExactInput: false,
                        oppositeAmountBound: 0,
                        amount: parseEther("1"),
                        sqrtPriceLimitX96: 0,
                        deadline: ethers.constants.MaxUint256,
                        referralCode: ethers.constants.HashZero,
                    }),
                )
                    .to.emit(clearingHouse, "PositionChanged")
                    .withArgs(
                        taker.address, // trader
                        baseToken.address, // baseToken
                        parseEther("-0.006673532984759078"), // exchangedPositionSize
                        parseEther("1.010101010101010102"), // exchangedPositionNotional
                        parseEther("0.010101010101010102"), // fee
                        parseEther("1"), // openNotional
                        parseEther("0"), // realizedPnl
                        "974684205576916525762591342066", // sqrtPriceAfterX96
                    )

                const [baseBalance, quoteBalance] = await clearingHouse.getTokenBalance(
                    taker.address,
                    baseToken.address,
                )
                expect(baseBalance).be.lt(parseEther("0"))
                expect(quoteBalance).be.deep.eq(parseEther("1"))

                expect(await getMakerFee()).be.closeTo(parseEther("0.010101010101010102"), 1)
                expect(await accountBalance.getTakerPositionSize(taker.address, baseToken.address)).to.be.eq(
                    parseEther("-0.006673532984759078"),
                )
            })
        })
    })

})
