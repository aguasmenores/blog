#!/usr/bin/python
from requests import get
from bs4 import BeautifulSoup
import json
import re

contact_list_fn = 'contact_info.tsv'
mail_list_fn = 'mails.csv'
fb_list_fn = 'fbs.tsv'
tw_list_fn = 'tw.tsv'

base_url = 'http://www.europarl.europa.eu'
search_url = 'http://www.europarl.europa.eu/meps/es/json/newperformsearchjson.html?bodyType=ALL&country='
country_code = 'ES'
response = get(search_url + country_code)

mep_json = json.loads(response.text)

mep_pages = []

for mj in mep_json['result']:
    mep_pages.append(mj['detailUrl'])

mep_mails = []

regex_mail = re.compile(r'mailto:(.+)\[dot\](.+)\[at\](.+)')
count_m = 0
count_f = 0
count_t = 0
mail_list = []
fb_list = []
tw_list = []
f_out = open(contact_list_fn, 'w')
for plink in mep_pages:
    p_response = get(base_url + plink,
                     headers={'User-Agent':
                              'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/60.0'})
    p_html = BeautifulSoup(p_response.text, 'html.parser')
    mep_name = p_html.find('li', class_='mep_name')
    if mep_name.a is not None:
        mep_name = mep_name.a['title']
    else:
        mep_name = mep_name.text
    link_collection = p_html.find_all('ul', class_='link_collection_noborder')
    m = link_collection[0].find('a', class_='link_email')
    f = link_collection[0].find('a', class_='link_fb')
    t = link_collection[0].find('a', class_='link_twitt')
    phones = link_collection[1].find_all('span', class_='phone')
    faxes = link_collection[1].find_all('span', class_='fax')
    mep_string = mep_name + "\t" + base_url + plink
    regex_phones_faxes = re.compile('([+0-9() ]+)[^0-9]+([0-9 ]+)')
    for ph in phones:
        print ph.text.decode('utf-8')
        mep_string += str("\t" + "phone:" + regex_phones_faxes.search(ph.text).group(1) +
                          regex_phones_faxes.search(ph.text).group(2))
    for fx in faxes:
        print fx.text.decode('utf-8')
        mep_string += str("\t" + "fax:" + regex_phones_faxes.search(fx.text).group(1) +
                          regex_phones_faxes.search(fx.text).group(2))
    if m is not None:
        mail_user = regex_mail.search(m['href']).group(3)[::-1]
        server_name = regex_mail.search(m['href']).group(2)[::-1]
        mail_domain = regex_mail.search(m['href']).group(1)[::-1]
        fqd = mail_user + '@' + server_name + "." + mail_domain
        count_m += 1
        mep_string += "\t" + fqd
        mail_list.append(fqd)
    else:
        mep_string += "\t"
    if f is not None:
        mep_string += "\t" + f['href']
        count_f += 1
        fb_list.append(f['href'])
    else:
        mep_string += "\t"
    if t is not None:
        mep_string += "\t" + t['href']
        count_t += 1
        tw_list.append(t['href'])
    else:
        mep_string += "\t"
    print mep_string.encode('utf-8')
    f_out.write(mep_string.encode('utf-8'))
f_out.close()

print "Writing e-mails ..." + str(mail_list_fn)
f = open(mail_list_fn, 'w')
f.write(','.join(mail_list))
f.close()

print "Writing Facebook profile URLs ..." + str(fb_list_fn)
f = open(fb_list_fn, 'w')
f.write('\t'.join(fb_list))
f.close()

print "Writing Twitter profile URLs ..." + str(tw_list_fn)
f = open(tw_list_fn, 'w')
f.write('\t'.join(tw_list))
f.close()

print "%d out of %d MEPs had an e-mail available." % (count_m, len(mep_pages))
print "%d out of %d MEPs had a Facebook account available." % (count_f, len(mep_pages))
print "%d out of %d MEPs had a Twitter account available." % (count_t, len(mep_pages))
