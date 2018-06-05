#!/usr/bin/python
from requests import get
from bs4 import BeautifulSoup
import re
import sys

base_url = 'http://gencat.cat/economia/resultats-parlament2017/09AU/'
base_page = 'DAU09000CI.htm'
response = get(base_url+base_page)

html_soup = BeautifulSoup(response.text, 'html.parser')
provinces = html_soup.find_all('div', class_='cajaiframe')

province_pages = []

chosen = None
regex_province = re.compile('muni([A-Za-z]+)')
regex_iframe_title = re.compile('Municipis')
for div in provinces:
    if regex_iframe_title.search(div.iframe['title']) is not None:
        province_name = regex_province.search(div.iframe['class'][3]).group(1)
        province_pages.append([province_name, div.iframe['src'], base_url+div.iframe['src']])


town_pages = []
for p_page in province_pages:
    p_response = get(p_page[2])
    p_html = BeautifulSoup(p_response.text, 'html.parser')
    link_elems = p_html.find_all('a')
    for link in link_elems:
        if link.parent.has_attr('class'):
            if link.parent['class'][0] == u'distritos':
                continue
        town_pages.append([p_page[0], link['title'], link['href'], base_url+link['href']])

town_pages.append(['Catalunya', 'Catalunya', 'DAU09999CM.htm',base_url+'DAU09999CM.htm'])

for t_page in town_pages:
    t_response = get(t_page[3])
    t_html = BeautifulSoup(t_response.text, 'html.parser')
    table = t_html.find('table', id='TVOTOS')
    rows = table.tbody.find_all('tr')
    votes = []
    for r in rows:
        party = r.th.text
        percent = r.find('td',title='Percentatge').text
        if party != '':
            votes.append((r.th.text,percent))
    votes.sort(key=lambda party: party[0])
    vote_string=''
    for pv in votes:
        vote_string+=pv[0].encode('utf-8')+";"+pv[1].encode('utf-8')+";"
    print '{};{};{}'.format(t_page[0].encode('utf-8'),t_page[1].encode('utf-8'),vote_string)
    


