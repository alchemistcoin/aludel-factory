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

  const fifoLib = await deploy("FIFO", {
    from: deployer,
    log: true,
  });

  const result = await deploy("AludelTimelock", {
    from: deployer,
    args: [],
    log: true,
    contract: "AludelTimelock",
    deterministicDeployment: false,
    libraries: {
      FIFO: fifoLib.address,
    },
  });

  const aludel = await ethers.getContractAt(result.abi, result.address);

  try {
    await (await aludel.initializeLock()).wait();
    log(`Aludel ${result.address} initialization locked.`);
  } catch (err) {
    log(
      `initialization failed, AludelTimelock ${result.address} was already initialized.`
    );
  }
};

deployFunc.tags = ["AludelTimelock"];
export default deployFunc;
