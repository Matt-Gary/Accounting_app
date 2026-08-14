"""
Pure portfolio calculation modules.

Nothing in this package touches the database, the network, or Flask. Every
function takes plain data and returns plain data, so the whole package is unit
testable without fixtures or credentials. `service/investment_service.py` owns
I/O and calls into here.
"""
