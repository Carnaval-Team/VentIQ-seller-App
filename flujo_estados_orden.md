# Flujo Completo de Estados de una Orden

## Apps involucradas

| App | Rol |
|-----|-----|
| **carnavalAPP** | Cliente - Crea la orden y puede cancelarla |
| **carnavalAdmin** | Administrador - Gestiona pagos, acepta/cancela órdenes, asigna repartidor |
| **carnaval-delivery** | Repartidor - Recoge y entrega la orden |

---

## Estados posibles de una orden

| # | Estado | Descripción |
|---|--------|-------------|
| 1 | **Pendiente de Pago** | Orden creada con método de pago por transferencia. Esperando que el cliente pague. |
| 2 | **En Revision** | El cliente dice que ya pagó (subió comprobante). Esperando que el admin valide. |
| 3 | **Nuevo** | Orden lista para ser aceptada por el admin (pago en efectivo o pago validado). |
| 4 | **Procesando** | El admin aceptó la orden. Se está preparando. |
| 5 | **Asignado** | El admin asignó un repartidor a la orden. |
| 6 | **Entregando** | El repartidor salió a entregar la orden. |
| 7 | **Completado** | La orden fue entregada al cliente exitosamente. |
| 8 | **Cancelado** | La orden fue cancelada (por el cliente o el admin). |

---

## Mapa de transiciones

```
                        ┌──────────────────────────────────────────────┐
                        │            CREACIÓN DE LA ORDEN              │
                        │              (carnavalAPP)                   │
                        └──────────────┬───────────────────────────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                      │
             Pago: Efectivo                      Pago: Transferencia
                    │                                      │
                    ▼                                      ▼
            ┌──────────────┐                    ┌────────────────────┐
            │    NUEVO     │                    │ PENDIENTE DE PAGO  │
            │  (Admin ve   │                    │  (Esperando que    │
            │   la orden)  │                    │   cliente pague)   │
            └──────┬───────┘                    └─────────┬──────────┘
                   │                                      │
                   │                          Cliente confirma pago
                   │                            (carnavalAPP)
                   │                                      │
                   │                                      ▼
                   │                            ┌────────────────────┐
                   │                            │    EN REVISION     │
                   │                            │ (Admin revisa el   │
                   │                            │   comprobante)     │
                   │                            └─────────┬──────────┘
                   │                                      │
                   │                          Admin valida el pago
                   │                            (carnavalAdmin)
                   │                                      │
                   │                                      ▼
                   │                              ┌──────────────┐
                   │                              │  PROCESANDO  │
                   │                              └──────┬───────┘
                   │                                     │
                   │    Admin acepta la orden             │
                   │      (carnavalAdmin)                 │
                   │              │                       │
                   └──────────────┼───────────────────────┘
                                  │
                                  ▼
                          ┌──────────────┐
                          │  PROCESANDO  │
                          │ (Preparando  │
                          │  la orden)   │
                          └──────┬───────┘
                                 │
                    Admin asigna repartidor
                      (carnavalAdmin)
                                 │
                ┌────────────────┴────────────────┐
                │                                  │
        Método entrega:                    Método entrega:
          Domicilio                       Entrega Cliente
                │                           (Recogida)
                ▼                                  │
        ┌──────────────┐                           │
        │   ASIGNADO   │                           │
        │ (Repartidor  │                           │
        │  notificado) │                           │
        └──────┬───────┘                           │
               │                                   │
    Repartidor presiona                            │
    "Salir a Entregar"                             │
    (carnaval-delivery)                            │
               │                                   │
               ▼                                   │
        ┌──────────────┐                           │
        │  ENTREGANDO  │                           │
        │ (En camino   │                           │
        │  al cliente) │                           │
        └──────┬───────┘                           │
               │                                   │
    Repartidor presiona                            │
      "Entregado"                                  │
    (carnaval-delivery)                            │
               │                                   │
               ▼                                   ▼
        ┌─────────────────────────────────────────────┐
        │                COMPLETADO                    │
        │  (Orden finalizada - cliente puede valorar)  │
        └──────────────────────────────────────────────┘


        ═══════════════════════════════════════════════
                      CANCELACIÓN
        ═══════════════════════════════════════════════

        Desde "Nuevo" o "Pendiente de Pago":
          → El CLIENTE puede cancelar (carnavalAPP)
          → El ADMIN puede cancelar (carnavalAdmin)

        Desde cualquier estado pre-entrega:
          → El ADMIN puede cancelar (carnavalAdmin)

                                 │
                                 ▼
                         ┌──────────────┐
                         │  CANCELADO   │
                         │ (Irreversible│
                         │  y final)    │
                         └──────────────┘
```

---

## Resumen por app: quién hace qué

### carnavalAPP (Cliente)
| Acción | Transición |
|--------|------------|
| Crear orden con pago en efectivo | → **Nuevo** |
| Crear orden con transferencia | → **Pendiente de Pago** |
| Confirmar que ya pagó (sube comprobante) | Pendiente de Pago → **En Revision** |
| Cancelar orden | Nuevo / Pendiente de Pago → **Cancelado** |
| Valorar orden | Solo disponible cuando está en **Completado** |

### carnavalAdmin (Administrador)
| Acción | Transición |
|--------|------------|
| Validar comprobante de pago | En Revision → **Procesando** |
| Aceptar orden nueva | Nuevo → **Procesando** |
| Asignar repartidor (domicilio) | Procesando → **Asignado** |
| Asignar repartidor (recogida/entrega cliente) | Procesando → **Completado** |
| Cancelar orden | Cualquier estado → **Cancelado** |

### carnaval-delivery (Repartidor)
| Acción | Transición |
|--------|------------|
| Presionar "Salir a Entregar" | Asignado → **Entregando** |
| Presionar "Entregado" | Entregando → **Completado** |

---

## Estados finales (sin salida)

- **Completado** - Fin exitoso
- **Cancelado** - Fin por cancelación (irreversible)
