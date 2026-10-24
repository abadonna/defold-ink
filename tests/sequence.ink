=== shuffle_cycle ===
{shuffle:
- One # variant:one
- Two # variant:two
- Three # variant:three
}
-> END

=== other_cycle ===
{shuffle:
- Red
- Green
- Blue
}
-> END

=== shuffle_once ===
{shuffle once:
- One
- Two
- Three
}
-> END

=== shuffle_stopping ===
{shuffle stopping:
- One
- Two
- Last
}
-> END

=== single ===
{shuffle:
- Alone
}
-> END

=== random_roll ===
Roll {RANDOM(1, 6)}
-> END
