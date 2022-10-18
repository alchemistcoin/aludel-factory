import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

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
  // hand-picked pseudo-leetspeak vanity name. No one will have the privkey for this
  const GEYSER_V2_VANITY_ADDRESS = '0x00000000000000000000000000000000be15efb2'

  log("Adding disabled GeyserV2 empty template to factory");
  // this is only meant to add previous programs, therefore it's disabled from the start
  try {
    await factory.addTemplate(GEYSER_V2_VANITY_ADDRESS, "GeyserV2", true);
  } catch {
    log("WARNING: GeyserV2 was already added");
  }
}

deployFunc.tags = ["GeyserV2Template"];
deployFunc.dependencies = ["AludelFactory"];
export default deployFunc;
