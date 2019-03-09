def float2hex(f):
			MAXHEXADECIMALS = 15
			w = f // 1
			d = f % 1

			# Do the whole:
			if w == 0: result = '0'
			else: result = ''
			while w:
				w, r = divmod(w, 16)
				r = int(r)
				if r > 9: r = chr(r+55)
				else: r = str(r)
				result =  r + result

			# And now the part:
			if d == 0: return result

			result += '.'
			count = 0
			while d:
				d = d * 16
				w, d = divmod(d, 1)
				w = int(w)
				if w > 9: w = chr(w+55)
				else: w = str(w)
				result +=  w
				count += 1
				if count > MAXHEXADECIMALS: break

			return result
