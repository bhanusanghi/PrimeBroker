import { expect } from "chai"
import { ethers } from "hardhat"

type contracts = {

  marginManager: any;
  marginAccount: any;
}

async function initializeContracts(): Promise<contracts> {
  //init margin manager
  const marginManagerFactory = await ethers.getContractFactory("MarginManager");
  const marginManager = await marginManagerFactory.deploy(
  )
  // create a user account using margin manager
  const marginAccountAddress = await marginManager.openMarginAccount();

  const marginAccount = (await ethers.getContractFactory("MarginAccount")).attach(marginAccountAddress)
  // return both

  return { marginAccount, marginManager };
}

describe("MarginManager", async () => {
  const [admin, bob] = await ethers.getSigners()
  beforeEach(async () => {
    const contracts: contracts = await initializeContracts();
    // put some money in margin account.
    
  })


})