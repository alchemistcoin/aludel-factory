import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { GEYSER_V2_VANITY_ADDRESS } from "../constants";

const deployFunc = async function ({
  ethers,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { get, log } = deployments;

  const deployedFactory = await get("AludelFactory");
  const factory = await ethers.getContractAt(
    deployedFactory.abi,
    deployedFactory.address
  );
  log("Adding disabled GeyserV2 empty template to factory");
  // this is only meant to add previous programs, therefore it's disabled from the start
  try {
    await factory.addTemplate(GEYSER_V2_VANITY_ADDRESS, "GeyserV2", true);
  } catch {
    log("WARNING: GeyserV2 was already added");
  }
};

deployFunc.tags = ["GeyserV2Template"];
deployFunc.dependencies = ["AludelFactory"];
export default deployFunc;
