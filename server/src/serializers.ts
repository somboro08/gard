// Lignes SQL → JSON de l'API (dates en ISO 8601 UTC, noms en camelCase).

type Row = Record<string, unknown>;
const iso = (d: unknown): string | null => (d instanceof Date ? d.toISOString() : null);

export const centerJson = (r: Row) => ({
  id: r.id,
  name: r.name,
  location: r.location,
  guardHours: r.guard_hours,
  tariff: {
    moto: r.price_moto,
    velo: r.price_velo,
    voiture: r.price_voiture,
    autre: r.price_autre,
  },
  role: r.role ?? undefined,
  createdAt: iso(r.created_at),
  updatedAt: iso(r.updated_at),
});

export const vehicleJson = (r: Row) => ({
  id: r.id,
  centerId: r.center_id,
  code: r.code,
  plate: r.plate,
  type: r.type,
  ownerName: r.owner_name,
  ownerPhone: r.owner_phone,
  note: r.note,
  depositedAt: iso(r.deposited_at),
  dueAt: iso(r.due_at),
  collectedAt: iso(r.collected_at),
  pickupCheck: r.pickup_check ?? null,
  ticketVerified: r.ticket_verified,
  price: r.price,
  paidAmount: r.paid_amount,
  updatedAt: iso(r.updated_at),
});

export const paymentJson = (r: Row) => ({
  id: r.id,
  vehicleId: r.vehicle_id,
  centerId: r.center_id,
  amount: r.amount,
  method: r.method,
  paidAt: iso(r.paid_at),
  plate: r.plate ?? undefined,
  ownerName: r.owner_name ?? undefined,
  vehicleType: r.vtype ?? undefined,
});

export const userJson = (r: Row) => ({ id: r.id, phone: r.phone, name: r.name });
