"""
Stubs the Supabase/dotenv layer so `service.investment_service` can be imported
in tests. Only the pure helpers in that module are exercised — anything that
actually touches `get_pg()` is out of scope here and belongs in the pure
`service/portfolio/` modules instead.
"""

import sys
import types


def _install_stubs():
    if 'supabase' not in sys.modules:
        supabase = types.ModuleType('supabase')
        supabase.create_client = lambda *a, **k: None
        supabase.Client = object
        sys.modules['supabase'] = supabase

    if 'dotenv' not in sys.modules:
        dotenv = types.ModuleType('dotenv')
        dotenv.load_dotenv = lambda *a, **k: None
        sys.modules['dotenv'] = dotenv

    if 'service.database' not in sys.modules:
        database = types.ModuleType('service.database')

        def _unavailable():
            raise RuntimeError(
                'get_pg() is not available in tests. Move the logic under test '
                'into service/portfolio/ so it can be tested without a database.'
            )

        database.get_pg = _unavailable
        sys.modules['service.database'] = database


_install_stubs()
