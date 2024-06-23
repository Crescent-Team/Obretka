		declare bencher: (suite: {[string]: {
		preRun: (() -> any)?,
		postRun: ((any) -> ())?,
		run: (any) -> (),
		numberOfCalls: number,
		}}) -> ()
	