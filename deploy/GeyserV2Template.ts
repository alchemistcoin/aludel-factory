import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { GEYSER_V2_VANITY_ADDRESS } from "../constants";

const deployFunc = async function ({
  ethers,
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { get, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployedFactory = await get("AludelFactory");
  const factory = (
    await ethers.getContractAt(deployedFactory.abi, deployedFactory.address)
  ).connect(await ethers.getSigner(deployer));
  log("Adding disabled GeyserV2 empty template to factory");
  // this is only meant to add previous programs, therefore it's disabled from the start
  try {
    await (
      await factory.addTemplate(GEYSER_V2_VANITY_ADDRESS, "GeyserV2", true)
    ).wait();
  } catch (err) {
    // cast sig 'TemplateAlreadyAdded()'
    if (err.data === "0xf298693e") {
      log("WARNING: GeyserV2 was already added");
    } else {
      throw err;
    }
  }
};

deployFunc.tags = ["GeyserV2Template"];
deployFunc.dependencies = ["AludelFactory"];
export default deployFunc;
