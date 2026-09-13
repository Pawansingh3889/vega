"""Business capabilities, one directory each, four files apiece.

    modules/<name>/
        __init__.py    handle(event, state) -> Result; PERMISSIONS
        contract.py    typed dataclasses; no secrets
        service.py     pure rules; no I/O
        repository.py  all I/O

service.py being pure is the load-bearing rule. A VAT box is arithmetic over
typed rows, so it must be testable without a database, and anything that needs
a connection to compute a filed figure has put the figure out of reach of a
unit test.
"""
