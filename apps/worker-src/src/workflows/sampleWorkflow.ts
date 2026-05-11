import { proxyActivities } from "@temporalio/workflow";

const { sayHello } = proxyActivities<{ sayHello(name: string): Promise<string> }>({
  startToCloseTimeout: "30 seconds",
});

export async function sampleWorkflow(name: string): Promise<string> {
  return sayHello(name);
}