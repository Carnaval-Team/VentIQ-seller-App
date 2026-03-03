-- RPC function to process ride completion payments.
-- Uses SECURITY DEFINER so it bypasses RLS on wallet_drivers,
-- allowing the CLIENT to trigger payment processing when completing a ride.

CREATE OR REPLACE FUNCTION muevete.complete_ride_payment(
  p_metodo_pago TEXT,
  p_client_uuid UUID,
  p_driver_id BIGINT,
  p_viaje_id BIGINT,
  p_precio_final NUMERIC
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = muevete
AS $$
DECLARE
  v_commission NUMERIC;
  v_net_amount NUMERIC;
  v_driver_balance NUMERIC;
  v_client_balance NUMERIC;
  v_new_driver_balance NUMERIC;
  v_wallet_exists BOOLEAN;
BEGIN
  -- Get current driver balance
  SELECT balance INTO v_driver_balance
  FROM wallet_drivers WHERE driver_id = p_driver_id;

  IF v_driver_balance IS NULL THEN
    v_driver_balance := 0;
  END IF;

  -- Check if driver wallet row exists
  SELECT EXISTS(SELECT 1 FROM wallet_drivers WHERE driver_id = p_driver_id)
  INTO v_wallet_exists;

  IF p_metodo_pago = 'wallet' THEN
    -- WALLET PAYMENT: client funds already held at acceptOffer
    -- 1) Record client transaction
    SELECT balance INTO v_client_balance
    FROM suscription_user WHERE user_id = p_client_uuid;

    INSERT INTO transacciones_wallet (user_id, tipo, monto, balance_despues, viaje_id, descripcion)
    VALUES (p_client_uuid, 'pago_viaje', -p_precio_final, v_client_balance, p_viaje_id, 'Pago de viaje por wallet');

    -- 2) Credit driver: fare minus 15% commission
    v_commission := p_precio_final * 0.15;
    v_net_amount := p_precio_final - v_commission;
    v_new_driver_balance := v_driver_balance + v_net_amount;

    IF v_wallet_exists THEN
      UPDATE wallet_drivers SET balance = v_new_driver_balance WHERE driver_id = p_driver_id;
    ELSE
      INSERT INTO wallet_drivers (driver_id, balance) VALUES (p_driver_id, v_new_driver_balance);
    END IF;

    INSERT INTO transacciones_wallet (driver_id, tipo, monto, balance_despues, viaje_id, descripcion)
    VALUES (p_driver_id, 'pago_viaje', v_net_amount, v_new_driver_balance, p_viaje_id,
            'Pago por viaje (tarifa $' || p_precio_final || ' - 15% comisión)');

  ELSE
    -- CASH PAYMENT: charge driver 15% commission
    v_commission := p_precio_final * 0.15;

    IF v_driver_balance < v_commission THEN
      RETURN json_build_object('success', false, 'error',
        'Saldo del conductor insuficiente para comisión de $' || v_commission);
    END IF;

    v_new_driver_balance := v_driver_balance - v_commission;

    IF v_wallet_exists THEN
      UPDATE wallet_drivers SET balance = v_new_driver_balance WHERE driver_id = p_driver_id;
    ELSE
      -- Should not happen (driver should have balance), but handle gracefully
      INSERT INTO wallet_drivers (driver_id, balance) VALUES (p_driver_id, v_new_driver_balance);
    END IF;

    INSERT INTO transacciones_wallet (driver_id, tipo, monto, balance_despues, viaje_id, descripcion)
    VALUES (p_driver_id, 'comision_viaje', -v_commission, v_new_driver_balance, p_viaje_id,
            'Comisión 15% por viaje completado');
  END IF;

  RETURN json_build_object('success', true, 'driver_balance', v_new_driver_balance);
END;
$$;
