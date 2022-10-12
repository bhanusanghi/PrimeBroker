import { ethers } from "ethers";

export const PERP = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("PERP"))
export const SNXUNI = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("SNXUNI"))
export const TRANSFERMARGIN = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("TRANSFERMARGIN"))
export const ERC20 = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ERC20"))
