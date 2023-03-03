LIST DoctorsInSurgery = (Adams), Bernard, Cartwright, (Denver), Eamonn

-> waiting_room

=== function whos_in_today()
	In the surgery today are {DoctorsInSurgery}.
	

=== function doctorEnters(who)
	{ DoctorsInSurgery !? who:
		~ DoctorsInSurgery += who
		Dr {who} arrives in a fluster.
	}

=== function doctorLeaves(who)
	{ DoctorsInSurgery ? who:
		~ DoctorsInSurgery -= who
		Dr {who} leaves for lunch.
	}

=== waiting_room
	{whos_in_today()}
	*	[Time passes...]
		{doctorLeaves(Adams)} {doctorEnters(Cartwright)} {doctorEnters(Eamonn)}
		{whos_in_today()}
	->END