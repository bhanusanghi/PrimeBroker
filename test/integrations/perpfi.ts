import { expect } from "chai"
import { ethers } from "hardhat"
import { erc20 } from "./addresses";
import { MarginManager, MarginAccount, ERC20 } from "../../typechain-types";

const ETHER = 10 ** 18
type contracts = {
  marginManager: MarginManager;
  marginAccount: MarginAccount;
  erc20: {
    usdc: ERC20;
  }
}

async function initializeContracts(): Promise<contracts> {
  //init margin manager
  const marginManagerFactory = await ethers.getContractFactory("MarginManager");
  const marginManager = await marginManagerFactory.deploy(
  )
  // create a user account using margin manager
  const marginAccountAddress: string = (await marginManager.openMarginAccount(erc20.usdc)) as any;

  const marginAccount = (await ethers.getContractFactory("MarginAccount")).attach(marginAccountAddress)

  const usdc = (await ethers.getContractFactory("ERC20")).attach(erc20.usdc)

  // return all

  return {
    marginAccount, marginManager, erc20: {
      usdc
    }
  };
}

describe("MarginManager", async () => {
  const [admin, bob] = await ethers.getSigners()
  beforeEach(async () => {
    const contracts: contracts = await initializeContracts();

    // account with usdc - 0xebe80f029b1c02862b9e8a70a7e5317c06f62cae
    const usdcHolder = await ethers.getImpersonatedSigner("0xebe80f029b1c02862b9e8a70a7e5317c06f62cae");
    // send usdc
    contracts.erc20.usdc.connect(usdcHolder).transfer(bob.address, 10000 * ETHER)
    // put some money in margin account.
    contracts.marginAccount.connect(bob).addCollateral(2000 * ETHER)
  })


})