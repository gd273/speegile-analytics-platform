# db_utils.py
from sqlalchemy import text


def log_load_error(conn, load_id, error_message, row_number=None, column_name=None):
    """Record an upload error. The caller owns the transaction and commits it."""
    try:
        conn.execute(text("""
            UPDATE public.load_master
            SET status = 'Fail'
            WHERE id = :lid
        """), {"lid": load_id})
        conn.execute(text("""
            INSERT INTO public.load_errors
                (load_id, row_number, column_name, error_message)
            VALUES
                (:lid, :row_num, :col_name, :err_msg)
        """), {
            "lid":      load_id,
            "row_num":  row_number,
            "col_name": column_name,
            "err_msg":  error_message
        })
        print(f"DEBUG: Error logged to load_errors for load_id={load_id}", flush=True)
    except Exception as log_err:
        print(f"DEBUG: Failed to log error: {log_err}", flush=True)
