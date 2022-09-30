import { ethers, network } from "hardhat"


export async function resetFork() {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          url: process.env.OPTIMISM_MAINNET_KEY || ''
        },
      },
    ],
  });
}