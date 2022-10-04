import { ethers } from "ethers";

export const PERP = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("PERP"))
export const ERC20 = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ERC20"))
