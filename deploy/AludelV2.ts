import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunc = async function ({
  ethers,
  getNamedAccounts,
  deployments,
}: HardhatRuntimeEnvironment) {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const result = await deploy("AludelV2", {
    from: deployer,
    args: [],
    log: true,
    contract: "src/contracts/aludel/AludelV2.sol:AludelV2",
    deterministicDeployment: false,
  });

  const aludel = await ethers.getContractAt(result.abi, result.address);

  try {
    await (await aludel.initializeLock()).wait();
    log(`Aludel ${result.address} initialization locked.`);
  } catch (err) {
    log(
      `initialization failed, Aludel ${result.address} was already initialized.`
    );
  }
};

deployFunc.tags = ["AludelV2"];
export default deployFunc;
