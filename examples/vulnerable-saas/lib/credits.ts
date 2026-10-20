import { db } from "./db";

export async function getBalance(tenantId: string): Promise<number> {
  const { rows } = await db.query(
    "SELECT balance FROM credit_balances WHERE tenant_id = $1",
    [tenantId],
  );
  return rows[0]?.balance ?? 0;
}

export async function debit(tenantId: string, amount: number): Promise<void> {
  const balance = await getBalance(tenantId);
  if (balance < amount) {
    throw new Error("insufficient credits");
  }
  await db.query("UPDATE credit_balances SET balance = $1 WHERE tenant_id = $2", [
    balance - amount,
    tenantId,
  ]);
}

export async function addCredits(tenantId: string, amount: number): Promise<void> {
  await db.query(
    `INSERT INTO credit_balances (tenant_id, balance) VALUES ($1, $2)
     ON CONFLICT (tenant_id) DO UPDATE SET balance = credit_balances.balance + EXCLUDED.balance`,
    [tenantId, amount],
  );
}
