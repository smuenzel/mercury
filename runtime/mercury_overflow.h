/*
** Copyright (C) 1995-1997 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/* mercury_overflow.h - definitions for overflow checks */

#ifndef MERCURY_OVERFLOW_H
#define MERCURY_OVERFLOW_H

#define IF(cond, val)	((cond) ? ((val), (void)0) : (void)0)

#ifdef SPEED

#define	heap_overflow_check()		((void)0)
#define	detstack_overflow_check()	((void)0)
#define	detstack_underflow_check()	((void)0)
#define	nondstack_overflow_check()	((void)0)
#define	nondstack_underflow_check()	((void)0)

#else /* not SPEED */

#include "mercury_regs.h"
#include "mercury_misc.h"	/* for fatal_error() */

#define	heap_overflow_check()					\
			(					\
				IF (MR_hp >= heap_zone->top,(	\
					fatal_error("heap overflow") \
				)),				\
				IF (MR_hp > heap_zone->max,(	\
					heap_zone->max = MR_hp	\
				)),				\
				(void)0				\
			)

#define	detstack_overflow_check()				\
			(					\
				IF (MR_sp >= detstack_zone->top,(	\
					fatal_error("stack overflow") \
				)),				\
				IF (MR_sp > detstack_zone->max,(	\
					detstack_zone->max = MR_sp	\
				)),				\
				(void)0				\
			)

#define	detstack_underflow_check()				\
			(					\
				IF (MR_sp < detstack_zone->min,(		\
					fatal_error("stack underflow") \
				)),				\
				(void)0				\
			)

#define	nondstack_overflow_check()				\
			(					\
				IF (MR_maxfr >= nondetstack_zone->top,(	\
					fatal_error("nondetstack overflow") \
				)),				\
				IF (MR_maxfr > nondetstack_zone->max,(	\
					nondetstack_zone->max = MR_maxfr	\
				)),				\
				(void)0				\
			)

#define	nondstack_underflow_check()				\
			(					\
				IF (MR_maxfr < nondetstack_zone->min,(	\
					fatal_error("nondetstack underflow") \
				)),				\
				(void)0				\
			)

#endif /* not SPEED */

#endif /* not MERCURY_OVERFLOW_H */
