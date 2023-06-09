import fs from "fs";
import { resolve } from "path";

export default function getConfigData(networkName: string) {
  const filePath = `${resolve("./configs")}/${networkName}.json`;

  try {
    const configs = JSON.parse(
      fs.readFileSync(filePath, { encoding: "utf-8" })
    );
    return configs;
  } catch (e) {
    return undefined;
  }
}
