import { ethers } from "ethers";

export const PERP = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("PERP"))
export const SNXUNI = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("SNXUNI"))
export const TRANSFERMARGIN = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("TRANSFERMARGIN"))
export const ERC20 = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ERC20"))
export const PERP_MARKET_KEY_AAVE = ethers.utils.formatBytes32String("PERP.AAVE");
export const SNX_MARKET_KEY_sUNI = ethers.utils.formatBytes32String("SNX.UNI");
export const DAYS = 86400; // seconds in day
export const WEEKS = 7 * DAYS;
export const SNX_MARKET_KEY_sETH = ethers.utils.formatBytes32String("SNX.sETH");
