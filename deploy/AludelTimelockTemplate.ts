import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = async function ({
  ethers,
  getNamedAccounts,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { get, log } = deployments;

  const aludelContract = await get("AludelTimelock");
  const { deployer } = await getNamedAccounts();
  const deployedFactory = await get("AludelFactory");
  const factory = await ethers.getContractAt(
    deployedFactory.abi,
    deployedFactory.address,
    await ethers.getSigner(deployer)
  );

  log("Adding working AludelTimelock templates to factory");
  try {
    await (
      await factory.addTemplate(aludelContract.address, "AludelTimelock", false)
    ).wait();
  } catch (err) {
    console.log(err);
    log("WARNING: AludelTimelock was already added");
  }
};

deployFunc.tags = ["AludelTimelockTemplate"];
deployFunc.dependencies = ["AludelFactory", "AludelTimelock"];
export default deployFunc;
