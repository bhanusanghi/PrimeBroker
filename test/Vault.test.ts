
import { expect } from "chai"
import { parseEther, parseUnits } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"

import { Vault } from "../typechain-types";
// import { parseEther, parseUnits } from "ethers/lib/utils"


describe("Vault test", () => {
  const [admin, alice, bob] = waffle.provider.getWallets()

  beforeEach(async () => {

    const price = "1"

    // await usdc.connect(alice).approve(vault.address, ethers.constants.MaxUint256)

    // await usdc.mint(bob.address, parseUnits("1000000", usdcDecimals))
  })

  describe("vault", () => {

    it("test", async () => {
      console.log('yolo');
      // expect(await vault.getBalanceByToken(alice.address, usdc.address)).to.be.eq(
      //   parseUnits("1000", usdcDecimals),
      // )
      // expect(await vault.getBalanceByToken(bob.address, weth.address)).to.be.eq(parseEther("10"))
    })
  })

})
