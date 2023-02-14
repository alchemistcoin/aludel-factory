import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = async function ({
  ethers,
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { deployer } = await getNamedAccounts();
  const { get, log } = deployments;

  const aludelContract = await get("AludelV2");

  const deployedFactory = await get("AludelFactory");
  const factory = (
    await ethers.getContractAt(deployedFactory.abi, deployedFactory.address)
  ).connect(await ethers.getSigner(deployer));

  log("Adding working AludelV2 templates to factory");
  try {
    await (
      await factory.addTemplate(aludelContract.address, "AludelV2", false)
    ).wait();
  } catch (err) {
    // cast sig 'TemplateAlreadyAdded()'
    if (err.data === "0xf298693e") {
      log("WARNING: AludelV2 was already added");
    } else {
      throw err;
    }
  }
};

deployFunc.tags = ["AludelV2Template"];
deployFunc.dependencies = ["AludelFactory", "AludelV2"];
export default deployFunc;
